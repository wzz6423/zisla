#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'json'

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

  private

  def status(state: 'open', labels:, type_label: nil)
    @contract.status_for(state: state, labels: labels, type_label: type_label)
  end

  def configured_types
    JSON.parse(File.read(PR_CONTRACT_PATH)).fetch('types')
  end
end
