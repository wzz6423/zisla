#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'open3'
require 'tmpdir'

require_relative 'project-metadata'
require_relative 'pr-metadata'

class ProjectMetadataTest < Minitest::Test
  CONTRACT_PATH = File.expand_path('../project-automation.json', __dir__)
  PR_CONTRACT_PATH = File.expand_path('../pr-automation.json', __dir__)

  def setup
    @contract = ProjectMetadata::Contract.load(CONTRACT_PATH)
    @pr_contract = PullRequestMetadata::Contract.load(PR_CONTRACT_PATH)
  end

  def test_fix_pr_body_routes_before_pr_automation_adds_the_label
    metadata = PullRequestMetadata.parse("## PR Type\n\n- Type: fix\n", @pr_contract)

    assert_equal 'bug', metadata['typeLabel']
    assert_equal 'Bug Fix', status(labels: [], type_label: metadata['typeLabel'])
  end

  def test_every_type_label_and_alias_routes_without_event_labels
    configured_types.each do |entry|
      values = [entry.fetch('type'), entry.fetch('label')] + Array(entry['aliases'])
      values << 'Bug Fix' if entry.fetch('type') == 'fix'
      expected = status(labels: [entry.fetch('label')])

      values.uniq.each do |value|
        metadata = PullRequestMetadata.parse("## PR Type\n\n- Type: #{value}\n", @pr_contract)

        assert_equal entry.fetch('label'), metadata['typeLabel'], value
        assert_equal expected, status(labels: [], type_label: metadata['typeLabel']), value
      end
    end
  end

  def test_issue_area_label_keeps_its_existing_route
    assert_equal 'Bug Fix', status(labels: ['area:bug-fix'])
  end

  def test_configured_label_priority_is_preserved
    assert_equal 'CI & Build', status(labels: ['area:ci-build'], type_label: 'bug')
  end

  def test_unknown_or_missing_labels_use_the_default_status
    assert_equal 'Inbox', status(labels: [])
    assert_equal 'Inbox', status(labels: ['unmanaged'], type_label: 'unknown')
  end

  def test_closed_items_always_move_to_done
    assert_equal 'Done', status(state: 'closed', labels: [], type_label: 'bug')
  end

  def test_rejects_non_array_label_json
    assert_raises(ProjectMetadata::ContractError) { ProjectMetadata.labels_from('{"label":"bug"}') }
  end

  def test_open_issue_and_pull_request_keep_their_submission_time
    %w[issue pull_request].each do |kind|
      event = event_for(kind, state: 'open')
      assert_equal({ 'createdAt' => '2026-10-03T16:30:00Z', 'endedAt' => nil },
                   ProjectMetadata.timestamps_for(event))
    end
  end

  def test_closed_issue_uses_its_close_time
    event = event_for('issue', state: 'closed', closed_at: '2026-10-04T02:30:00Z')

    assert_equal '2026-10-04T02:30:00Z', ProjectMetadata.timestamps_for(event)['endedAt']
  end

  def test_merged_pull_request_uses_merge_time
    event = event_for('pull_request', state: 'closed',
                      closed_at: '2026-10-04T02:29:59Z', merged_at: '2026-10-04T02:30:00Z')

    assert_equal '2026-10-04T02:30:00Z', ProjectMetadata.timestamps_for(event)['endedAt']
  end

  def test_closed_unmerged_pull_request_uses_close_time
    event = event_for('pull_request', state: 'closed', closed_at: '2026-10-04T02:30:00Z')

    assert_equal '2026-10-04T02:30:00Z', ProjectMetadata.timestamps_for(event)['endedAt']
  end

  def test_reopened_item_clears_end_time_and_repeated_events_are_stable
    event = event_for('issue', state: 'open', closed_at: nil)
    expected = { 'createdAt' => '2026-10-03T16:30:00Z', 'endedAt' => nil }

    assert_equal expected, ProjectMetadata.timestamps_for(event)
    assert_equal expected, ProjectMetadata.timestamps_for(event)
  end

  def test_missing_event_times_fail_before_project_writes
    assert_raises(ProjectMetadata::ContractError) { ProjectMetadata.timestamps_for({}) }
    assert_raises(KeyError) { ProjectMetadata.timestamps_for('issue' => { 'state' => 'open' }) }
    assert_raises(ProjectMetadata::ContractError) do
      ProjectMetadata.timestamps_for(event_for('issue', state: 'closed'))
    end
  end

  def test_dates_command_reads_the_event_payload
    Dir.mktmpdir('zisla-project-metadata-') do |directory|
      event_path = File.join(directory, 'event.json')
      File.write(event_path, JSON.generate(event_for('pull_request', state: 'closed',
                                                   closed_at: '2026-10-05T02:30:00Z')))
      output, error, status = Open3.capture3('ruby', File.expand_path('project-metadata.rb', __dir__),
                                             'dates', '--event-file', event_path)

      assert status.success?, error
      assert_equal({ 'submittedDate' => '2026-10-04', 'endDate' => '2026-10-05' }, JSON.parse(output))
    end
  end

  def test_project_dates_use_the_same_beijing_day_as_the_visible_timeline
    event = event_for('pull_request', state: 'closed', closed_at: '2026-10-04T02:30:00Z')

    assert_equal({ 'submittedDate' => '2026-10-04', 'endDate' => '2026-10-04' },
                 ProjectMetadata.dates_for(event))
    assert_equal '2026-10-04 00:30:00 +08:00',
                 ProjectMetadata.local_time('2026-10-03T16:30:00Z').strftime('%F %T %:z')
  end

  def test_open_item_has_no_project_end_date
    assert_nil ProjectMetadata.dates_for(event_for('issue', state: 'open'))['endDate']
  end

  def test_invalid_timestamp_fails_before_project_writes
    event = event_for('issue', state: 'open')
    event['issue']['created_at'] = 'yesterday'

    assert_raises(ProjectMetadata::ContractError) { ProjectMetadata.dates_for(event) }
  end

  def test_pull_request_dates_include_the_project_schedule
    event = event_for('pull_request', state: 'open')
    event['pull_request']['body'] = "## GitHub Project\n- Start date: 2026-10-01\n- Target date: 2026-10-10\n"

    assert_equal({ 'submittedDate' => '2026-10-04', 'endDate' => nil,
                   'startDate' => '2026-10-01', 'targetDate' => '2026-10-10' },
                 ProjectMetadata.dates_for(event))
  end

  def test_issue_body_cannot_set_the_pull_request_schedule
    event = event_for('issue', state: 'open')
    event['issue']['body'] = "## GitHub Project\n- Start date: invalid\n- Target date: 2026-10-10\n"

    assert_equal({ 'submittedDate' => '2026-10-04', 'endDate' => nil }, ProjectMetadata.dates_for(event))
  end

  def test_invalid_pull_request_schedule_exits_without_date_output
    Dir.mktmpdir('zisla-project-metadata-') do |directory|
      event = event_for('pull_request', state: 'open')
      event['pull_request']['body'] = "## GitHub Project\n- Target date: 2026-02-30\n"
      event_path = File.join(directory, 'event.json')
      File.write(event_path, JSON.generate(event))
      output, error, status = Open3.capture3('ruby', File.expand_path('project-metadata.rb', __dir__),
                                           'dates', '--event-file', event_path)

      refute status.success?
      assert_empty output
      assert_includes error, 'Target date'
      refute_includes error, 'from '
    end
  end

  private

  def status(state: 'open', labels:, type_label: nil)
    @contract.status_for(state: state, labels: labels, type_label: type_label)
  end

  def configured_types
    JSON.parse(File.read(PR_CONTRACT_PATH)).fetch('types')
  end

  def event_for(kind, state:, closed_at: nil, merged_at: nil)
    { kind => { 'state' => state, 'created_at' => '2026-10-03T16:30:00Z',
                'closed_at' => closed_at, 'merged_at' => merged_at } }
  end
end
