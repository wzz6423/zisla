#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'open3'
require 'tmpdir'

require_relative 'timeline-metadata'

class TimelineMetadataTest < Minitest::Test
  def test_issue_submission_uses_beijing_time_and_keeps_current_body
    result = TimelineMetadata.render(event_for('issue', 'open'), "Current user edit\n")

    assert result['changed']
    assert_includes result['body'], "Current user edit\n\n<!-- zisla-timeline:start -->\n## Timeline"
    assert_includes result['body'], '- Submitted: 2026-10-04 00:30:00 UTC+08:00'
    refute_includes result['body'], '- Ended:'
  end

  def test_empty_body_starts_with_a_submission_time
    result = TimelineMetadata.render(event_for('issue', 'open'), nil)

    assert result['body'].start_with?(TimelineMetadata::START_MARKER)
    assert_includes result['body'], '- Submitted: 2026-10-04 00:30:00 UTC+08:00'
  end

  def test_closed_issue_and_merged_pull_request_show_the_end_time
    issue = TimelineMetadata.render(event_for('issue', 'closed', closed_at: '2026-10-04T02:30:00Z'), '')
    pull_request = TimelineMetadata.render(event_for('pull_request', 'closed',
                                                     closed_at: '2026-10-04T02:29:59Z',
                                                     merged_at: '2026-10-04T02:30:00Z'), '')

    assert_includes issue['body'], '- Ended: 2026-10-04 10:30:00 UTC+08:00'
    assert_equal issue['body'], pull_request['body']
  end

  def test_repeated_sync_is_stable_and_reopen_removes_the_end_time
    closed_event = event_for('issue', 'closed', closed_at: '2026-10-04T02:30:00Z')
    closed_body = TimelineMetadata.render(closed_event, 'User text')['body']
    repeated = TimelineMetadata.render(closed_event, closed_body)

    refute repeated['changed']
    assert_equal closed_body, repeated['body']

    reopened = TimelineMetadata.render(event_for('issue', 'open'), closed_body)
    assert reopened['changed']
    refute_includes reopened['body'], '- Ended:'
    assert_equal 1, reopened['body'].scan(TimelineMetadata::START_MARKER).length
  end

  def test_edit_after_timeline_is_preserved
    initial = TimelineMetadata.render(event_for('issue', 'open'), 'First line')['body']
    current = "#{initial}\nNew user edit"

    updated = TimelineMetadata.render(event_for('issue', 'open'), current)

    assert_includes updated['body'], 'First line'
    assert_includes updated['body'], 'New user edit'
    assert_equal 1, updated['body'].scan(TimelineMetadata::START_MARKER).length
  end

  def test_cli_uses_current_resource_state_when_an_old_event_is_replayed
    Dir.mktmpdir('zisla-timeline-') do |directory|
      event_path = File.join(directory, 'event.json')
      resource_path = File.join(directory, 'resource.json')
      %w[issue pull_request].product(%w[open closed]).each do |kind, state|
        old_state = state == 'open' ? 'closed' : 'open'
        File.write(event_path, JSON.generate(event_for(kind, old_state, closed_at: '2026-10-04T02:30:00Z')))
        current = event_for(kind, state, closed_at: '2026-10-05T02:30:00Z').fetch(kind).merge('body' => 'Current body')
        File.write(resource_path, JSON.generate(current))
        output, error, status = Open3.capture3('ruby', File.expand_path('timeline-metadata.rb', __dir__),
                                               '--event-file', event_path, '--resource-file', resource_path)

        assert status.success?, error
        body = JSON.parse(output).fetch('body')
        assert_includes body, 'Current body'
        if state == 'closed'
          assert_includes body, '- Ended: 2026-10-05 10:30:00 UTC+08:00'
        else
          refute_includes body, '- Ended:'
        end
      end
    end
  end

  private

  def event_for(kind, state, closed_at: nil, merged_at: nil)
    { kind => { 'state' => state, 'created_at' => '2026-10-03T16:30:00Z',
                'closed_at' => closed_at, 'merged_at' => merged_at } }
  end
end
