#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'json'

require_relative 'pr-metadata'

class PullRequestMetadataTest < Minitest::Test
  CONTRACT_PATH = File.expand_path('../pr-automation.json', __dir__)

  def setup
    @contract = PullRequestMetadata::Contract.load(CONTRACT_PATH)
  end

  def test_accepts_a_complete_body
    assert_empty validate('ci(github): add pull request automation')
  end

  def test_reports_missing_sections
    errors = PullRequestMetadata.validate(title: 'ci: add automation', body: "## Summary\n\n- Work.\n", contract: @contract)

    assert_includes errors.join("\n"), '## PR Type'
    assert_includes errors.join("\n"), '## AI Attribution'
  end

  def test_requires_visible_summary_content
    ['', '   ', '<!-- Describe the change. -->', '-', '*', '+', '1.', '1)', '- [ ]', '- [x]', '- [X]',
     '- <!-- Describe the change. -->'].each do |summary|
      body = build_body.sub('- Add pull request automation.', summary)
      errors = PullRequestMetadata.validate(title: 'ci: add automation', body: body, contract: @contract)

      assert_includes errors.join("\n"), 'Summary must include a non-empty description.', summary.inspect
    end

    ['Validate PR metadata.', '- [ ] Validate PR metadata.', '1. Validate PR metadata.'].each do |summary|
      body = build_body.sub('- Add pull request automation.', summary)
      assert_empty PullRequestMetadata.validate(title: 'ci: add automation', body: body, contract: @contract)
    end
  end

  def test_requires_each_risk_and_rollback_field
    { 'Risk' => 'Repository automation only.', 'Rollback' => 'Revert this pull request.' }.each do |field, value|
      ['', '   ', '<!-- Describe this field. -->'].each do |replacement|
        body = build_body.sub("- #{field}: #{value}", "- #{field}: #{replacement}")
        errors = PullRequestMetadata.validate(title: 'ci: add automation', body: body, contract: @contract)

        assert_includes errors.join("\n"), "Risk and Rollback must declare exactly one non-empty #{field} field."
      end

      body = build_body.sub("- #{field}: #{value}", "- #{field}: #{value}\n- #{field}: Conflicting value.")
      errors = PullRequestMetadata.validate(title: 'ci: add automation', body: body, contract: @contract)
      assert_includes errors.join("\n"), "Risk and Rollback must declare exactly one non-empty #{field} field."
    end
  end

  def test_rejects_a_non_conventional_title
    assert_includes validate('add automation').join("\n"), 'Conventional Commit'
  end

  def test_rejects_a_non_ascii_title
    assert_includes validate('ci: 增加自动化').join("\n"), 'Conventional Commit'
  end

  def test_rejects_a_type_that_disagrees_with_the_title
    errors = validate('fix(github): add pull request automation')

    assert_includes errors.join("\n"), 'does not match the title type'
  end

  def test_rejects_an_unknown_type
    errors = validate('ci: add automation', type: 'emergency-fix')

    assert_includes errors.join("\n"), 'is not allowed'
  end

  def test_resolves_every_configured_type_label_and_alias
    configured_types.each do |entry|
      ([entry.fetch('type'), entry.fetch('label')] + Array(entry['aliases'])).uniq.each do |value|
        metadata = parse(type: value)

        assert_equal entry.fetch('type'), metadata['type'], value
        assert_equal entry.fetch('label'), metadata['typeLabel'], value
      end
    end
  end

  def test_normalizes_fix_alias_spellings
    ['bug', 'Bug Fix', 'bug_fix', 'BUG-FIX', 'bugfix', 'Hot Fix', 'hot_fix', 'HOT-FIX', 'hotfix'].each do |value|
      metadata = parse(type: value)

      assert_equal 'fix', metadata['type'], value
      assert_equal 'bug', metadata['typeLabel'], value
    end
  end

  def test_accepts_type_aliases_that_resolve_to_the_title_type
    ['bug', 'Bug Fix', 'bugfix', 'hotfix'].each do |value|
      assert_empty validate('fix: add automation', type: value), value
    end
  end

  def test_rejects_a_type_alias_with_extra_untrusted_content
    metadata = parse(type: 'bug; $(id)')

    assert_nil metadata['type']
    assert_nil metadata['typeLabel']
    assert_includes validate('fix: add automation', type: 'bug; $(id)').join("\n"), 'is not allowed'
  end

  def test_rejects_more_than_one_type
    errors = validate('ci: add automation', type: "ci\n- Type: fix")

    assert_includes errors.join("\n"), 'exactly one'
  end

  def test_requires_the_configured_github_project
    assert_includes validate('ci: add automation', project: '').join("\n"), 'GitHub Project must declare exactly one'
    assert_includes validate('ci: add automation', project: 'another project').join("\n"), 'must be "zisla Development"'
    assert_empty validate('ci: add automation')
  end

  def test_project_dates_accept_calendar_dates_and_ignore_other_sections
    body = build_body(start_date: '2024-02-29', target_date: '2026-10-10')
    body += "\n## Notes\n- Start date: invalid\n"
    sections = PullRequestMetadata.sections(body)

    assert_equal({ 'startDate' => '2024-02-29', 'targetDate' => '2026-10-10' },
                 PullRequestMetadata.project_dates(sections['GitHub Project']))
    assert_empty PullRequestMetadata.validate(title: 'ci: add automation', body: body, contract: @contract)
  end

  def test_project_date_parser_preserves_legacy_partial_schedules_and_ignores_comments
    [nil, [], ['- Start date:', '- Target date:   ']].each do |lines|
      assert_equal({ 'startDate' => nil, 'targetDate' => nil }, PullRequestMetadata.project_dates(lines))
    end
    body = "## GitHub Project\r\n- Start date: <!-- YYYY-MM-DD -->\r\n- Target date: 2026-10-10 <!-- plan -->\r\n<!--\r\n- Start date: invalid\r\n-->\r\n"

    assert_equal({ 'startDate' => nil, 'targetDate' => '2026-10-10' },
                 PullRequestMetadata.project_dates(PullRequestMetadata.sections(body)['GitHub Project']))
  end

  def test_pr_quality_requires_each_project_date
    { start_date: 'Start date', target_date: 'Target date' }.each do |key, label|
      [nil, '', '   ', '<!-- YYYY-MM-DD -->'].each do |value|
        errors = validate('ci: add automation', **{ key => value })

        assert_includes errors.join("\n"), "GitHub Project must declare exactly one non-empty #{label} field.", value.inspect
      end
    end
    errors = validate('ci: add automation', start_date: nil, target_date: nil)
    ['Start date', 'Target date'].each { |label| assert_includes errors.join("\n"), label }
  end

  def test_pr_quality_cannot_borrow_dates_from_other_sections_or_comments
    ["## Notes\n- Start date: 2026-10-05\n- Target date: 2026-10-12",
     "<!--\n- Start date: 2026-10-05\n- Target date: 2026-10-12\n-->"].each do |extra|
      body = build_body(start_date: nil, target_date: nil).sub('## PR Type', "#{extra}\n\n## PR Type")
      errors = PullRequestMetadata.validate(title: 'ci: add automation', body: body, contract: @contract)

      ['Start date', 'Target date'].each { |label| assert_includes errors.join("\n"), "non-empty #{label}" }
    end
  end

  def test_pr_quality_requires_target_date_on_or_after_start_date
    assert_empty validate('ci: add automation', start_date: '2026-10-05', target_date: '2026-10-05')
    assert_empty validate('ci: add automation', start_date: '2026-12-31', target_date: '2027-01-01')

    [['2026-10-05', '2026-10-04'], ['2026-01-01', '2025-12-31']].each do |start_date, target_date|
      errors = validate('ci: add automation', start_date: start_date, target_date: target_date)

      assert_includes errors.join("\n"), 'Target date must be on or after Start date.'
    end
  end

  def test_project_dates_reject_invalid_calendar_dates_formats_and_untrusted_values
    invalid = ['2026-02-29', '2026-02-30', '2026-13-01', '2026-00-01', '2026-10-00',
               '2026-4-1', '20261005', '2026-W41-1', '2026-278', '2026-10-05T00:00:00Z',
               'YYYY-MM-DD', 'TBD', 'None', 'tomorrow', '2026-10-05; $(id)', '2026-10-05`id`', '2026-10-05\\nextra']
    { start_date: 'Start date', target_date: 'Target date' }.each do |key, field|
      invalid.each do |value|
        errors = validate('ci: add automation', **{ key => value })

        assert_includes errors.join("\n"), "#{field} must be a valid date in YYYY-MM-DD format.", value
      end
    end
  end

  def test_project_dates_reject_duplicate_values
    { start_date: 'Start date', target_date: 'Target date' }.each do |key, field|
      ['', '<!-- unused -->', '2026-10-05', '2026-10-10'].each do |duplicate|
        errors = validate('ci: add automation', **{ key => "2026-10-05\n- #{field}: #{duplicate}" })

        assert_includes errors.join("\n"), "GitHub Project must declare exactly one non-empty #{field} field."
      end
    end
  end

  def test_requires_validation_status_and_fields
    assert_includes validate('ci: add automation', validation: '- Status: skipped').join("\n"), 'one exact status'
    assert_includes validate('ci: add automation', validation: '- Status: passed').join("\n"), 'non-empty Command'
    assert_includes validate('ci: add automation', validation: "- Status: passed\n- Command: rake").join("\n"), 'non-empty Result'
    assert_includes validate('ci: add automation', validation: '- Status: not run').join("\n"), 'non-empty Reason'
    assert_empty validate('ci: add automation', validation: "- Status: not run\n- Reason: No runnable target.")
  end

  def test_ignores_template_comments_when_reading_fields
    assert_includes validate('ci: add automation', validation: "- Status: passed\n- Command: <!-- required -->").join("\n"), 'non-empty Command'
  end

  def test_accepts_multiple_complete_validation_entries
    validation = "- Status: passed\n- Command: rake unit\n- Result: 10 passed.\n\n" \
                 "- Status: failed\n- Command: rake integration\n- Result: 1 failed.\n\n" \
                 "- Status: not run\n- Reason: UI was not changed."

    assert_empty validate('ci: add automation', validation: validation)
  end

  def test_rejects_invalid_or_empty_status_in_later_validation_entries
    ['skipped', '', '   ', '<!-- passed, failed, or not run -->'].each do |status|
      validation = "- Status: passed\n- Command: rake\n- Result: 10 passed.\n- Status: #{status}"
      errors = validate('ci: add automation', validation: validation)

      assert_includes errors.join("\n"), 'Validation entry 2 must declare one exact status', status.inspect
    end
  end

  def test_requires_fields_in_each_validation_entry
    { 'passed' => %w[Command Result], 'failed' => %w[Command Result], 'not run' => ['Reason'] }.each do |status, fields|
      validation = "- Status: passed\n- Command: rake\n- Result: 10 passed.\n- Reason: Earlier entry.\n- Status: #{status}"
      errors = validate('ci: add automation', validation: validation)

      fields.each do |field|
        assert_includes errors.join("\n"), "Validation entry 2 must include a non-empty #{field}", status
      end
    end
  end

  def test_validation_entries_cannot_borrow_fields_from_a_later_entry
    { 'passed' => %w[Command Result], 'failed' => %w[Command Result], 'not run' => ['Reason'] }.each do |status, fields|
      validation = "- Status: #{status}\n- Status: passed\n- Command: rake\n- Result: 10 passed.\n- Reason: Later entry."
      errors = validate('ci: add automation', validation: validation)

      fields.each do |field|
        assert_includes errors.join("\n"), "Validation entry 1 must include a non-empty #{field}", status
      end
    end
  end

  def test_rejects_duplicate_non_empty_fields_within_a_validation_entry
    %w[Command Result Reason].each do |field|
      validation = "- Status: passed\n- Command: rake\n- Result: 10 passed.\n- Reason: Context.\n- #{field}: Conflicting value."
      errors = validate('ci: add automation', validation: validation)

      assert_includes errors.join("\n"), "Validation entry 1 must declare at most one non-empty #{field}", field
    end
  end

  def test_validation_ignores_commented_entries_and_empty_optional_fields_with_crlf
    validation = "<!--\n- Status: skipped\n- Command: ignored\n-->\n" \
                 "- Status: passed <!-- selected -->\n- Command: rake\n- Command: <!-- unused -->\n- Result: 10 passed.\n" \
                 "- Status: not run\n- Command: <!-- unused -->\n- Result:\n- Reason: UI was not changed."
    body = build_body(validation: validation).gsub("\n", "\r\n")

    assert_empty PullRequestMetadata.validate(title: 'ci: add automation', body: body, contract: @contract)
  end

  def test_rejects_comment_placeholders_in_later_required_validation_fields
    { 'passed' => %w[Command Result], 'failed' => %w[Command Result], 'not run' => ['Reason'] }.each do |status, fields|
      validation = "- Status: passed\n- Command: rake\n- Result: 10 passed.\n- Status: #{status}\n" \
                   "- Command: <!-- required -->\n- Result: <!-- required -->\n- Reason: <!-- required -->"
      errors = validate('ci: add automation', validation: validation)

      fields.each do |field|
        assert_includes errors.join("\n"), "Validation entry 2 must include a non-empty #{field}", status
      end
    end
  end

  def test_related_issue_accepts_a_closing_keyword
    metadata = parse(related: 'Closes #123')

    assert_equal [123], metadata['issues']
    assert_includes PullRequestMetadata.labels(metadata, @contract), 'development'
    assert_empty validate('ci: add automation', related: 'Closes #123')
  end

  def test_related_issue_accepts_a_closing_url
    metadata = parse(related: 'Fixes https://github.com/wzz6423/zisla/issues/42')

    assert_equal [42], metadata['issues']
  end

  def test_related_issue_ignores_a_bare_reference
    assert_includes validate('ci: add automation', related: 'See #123').join("\n"), 'closing keyword'
  end

  def test_related_issue_rejects_none_together_with_a_reference
    errors = validate('ci: add automation', related: "None\nCloses #7")

    assert_includes errors.join("\n"), 'cannot be both'
  end

  def test_related_issue_none_must_be_the_entire_visible_section
    ["None\nSee #123", "- None\n- None", "None\nUnrelated text."].each do |related|
      assert_includes validate('ci: add automation', related: related).join("\n"), 'or exactly "None"'
    end
  end

  def test_related_issue_without_an_issue_has_no_development_label
    refute_includes PullRequestMetadata.labels(parse, @contract), 'development'
  end

  def test_declared_agent_requires_a_coauthor_trailer
    attribution = '- Agent: Claude Code (claude-opus-5)'

    assert_includes validate('ci: add automation', attribution: attribution).join("\n"), 'Co-authored-by'
  end

  def test_declared_agent_with_a_trailer_adds_the_ai_label
    attribution = "- Agent: Claude Code (claude-opus-5)\n- Co-authored-by: Claude <noreply@anthropic.com>"
    metadata = parse(attribution: attribution)

    assert_equal 'Claude Code (claude-opus-5)', metadata['agent']
    assert_equal ['Claude <noreply@anthropic.com>'], metadata['coAuthors']
    assert_includes PullRequestMetadata.labels(metadata, @contract), 'ai-assisted'
    assert_empty validate('ci: add automation', attribution: attribution)
  end

  def test_rejects_a_malformed_coauthor_trailer
    attribution = "- Agent: Claude Code\n- Co-authored-by: Claude"

    assert_includes validate('ci: add automation', attribution: attribution).join("\n"), 'Name <email>'
  end

  def test_rejects_a_coauthor_trailer_without_an_agent
    attribution = "- Agent: None\n- Co-authored-by: Claude <noreply@anthropic.com>"

    assert_includes validate('ci: add automation', attribution: attribution).join("\n"), 'Agent: None'
  end

  def test_requires_an_agent_field
    assert_includes validate('ci: add automation', attribution: '- Author: human').join("\n"), '- Agent:'
  end

  def test_rejects_multiple_agent_fields_instead_of_reading_only_the_first
    ['None', 'Codex'].each do |first|
      errors = validate('ci: add automation', attribution: "- Agent: #{first}\n- Agent: Codex")

      assert_includes errors.join("\n"), 'exactly one non-empty "- Agent:'
    end
  end

  def test_agent_none_needs_no_trailer
    assert_empty validate('ci: add automation', attribution: '- Agent: none')
    assert_nil parse(attribution: '- Agent: none')['agent']
  end

  def test_repository_template_needs_only_its_own_fields_filled_in
    template = File.read(File.expand_path('../PULL_REQUEST_TEMPLATE.md', __dir__))
                   .sub('<!-- Describe the purpose and implementation in English. -->', '- Validate all PR fields.')
                   .sub(/^- Start date:.*$/, '- Start date: 2026-10-05')
                   .sub(/^- Target date:.*$/, '- Target date: 2026-10-12')
                   .sub(/^- Type:$/, '- Type: ci')
                   .sub(/^- Status:.*$/, '- Status: not run')
                   .sub(/^- Reason:.*$/, '- Reason: Automation only.')
                   .sub(/^- Risk:.*$/, '- Risk: Repository automation only.')
                   .sub(/^- Rollback:.*$/, '- Rollback: Revert this pull request.')
    metadata = PullRequestMetadata.parse(template, @contract)

    # The comment above the Related Issue placeholder documents `Closes #123`, so
    # a contributor who keeps the invisible comments must not have that issue
    # linked, labelled or reported as contradicting the `None` they left in place.
    assert_empty metadata['issues']
    assert_equal ['ci'], PullRequestMetadata.labels(metadata, @contract)
    assert_empty PullRequestMetadata.validate(title: 'ci: fill in the template', body: template, contract: @contract)
  end

  def test_repository_template_declares_every_required_section
    template = File.read(File.expand_path('../PULL_REQUEST_TEMPLATE.md', __dir__))
    sections = PullRequestMetadata.sections(template)

    PullRequestMetadata::REQUIRED_SECTIONS.each do |section|
      assert_includes sections.keys, section
    end
  end

  private

  def validate(title, **overrides)
    PullRequestMetadata.validate(title: title, body: build_body(**overrides), contract: @contract)
  end

  def parse(**overrides)
    PullRequestMetadata.parse(build_body(**overrides), @contract)
  end

  def configured_types
    JSON.parse(File.read(CONTRACT_PATH)).fetch('types')
  end

  def build_body(type: 'ci', project: 'zisla Development', start_date: '2026-10-05', target_date: '2026-10-12',
                 validation: nil, related: 'None', attribution: '- Agent: None')
    <<~BODY
      ## Summary

      - Add pull request automation.

      ## GitHub Project

      - Project: #{project}
      #{"- Start date: #{start_date}" unless start_date.nil?}
      #{"- Target date: #{target_date}" unless target_date.nil?}

      ## PR Type

      - Type: #{type}

      ## Validation

      #{validation || "- Status: passed\n- Command: ruby .github/scripts/pr-metadata-test.rb\n- Result: 0 failures."}

      ## Risk and Rollback

      - Risk: Repository automation only.
      - Rollback: Revert this pull request.

      ## Related Issue

      #{related}

      ## AI Attribution

      #{attribution}
    BODY
  end
end
