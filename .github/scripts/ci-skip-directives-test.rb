#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'tmpdir'

require_relative 'ci-skip-directives'

class CiSkipDirectivesTest < Minitest::Test
  MANIFEST = {
    'workflows' => [
      { 'name' => 'Swift Tests', 'file' => 'swift-tests.yml', 'aliases' => ['swift'], 'checks' => ['Swift Tests', 'CodeQL (swift)'] },
      { 'name' => 'Web CI', 'file' => 'web-ci.yml', 'aliases' => ['web'], 'checks' => ['Web Build & Test'] }
    ]
  }.freeze

  def test_skip_all_from_owner_selects_every_workflow
    decision = resolve([comment('owner', 'OWNER', 'skip-all')])

    assert_equal true, decision['skipAll']
    assert_equal ['Swift Tests', 'Web CI'], decision['workflows']
    assert_equal ['Swift Tests', 'CodeQL (swift)', 'Web Build & Test'], decision['checks']
  end

  def test_trailing_text_and_separators_are_kept_as_a_note
    decision = resolve([comment('owner', 'OWNER', 'skip-all: documentation only change')])

    assert_equal ['Swift Tests', 'Web CI'], decision['workflows']
    assert_equal 'documentation only change', decision['directives'].first['note']
  end

  def test_unauthorized_author_is_ignored
    decision = resolve([comment('stranger', 'NONE', 'skip-all')])

    assert_empty decision['workflows']
    assert_empty decision['directives']
  end

  def test_requested_reviewer_is_authorized
    decision = resolve([comment('reviewer', 'NONE', 'skip-web')], reviewers: ['Reviewer'])

    assert_equal ['Web CI'], decision['workflows']
  end

  def test_bot_comments_are_ignored
    decision = resolve([comment('github-actions[bot]', 'OWNER', 'skip-all')])

    assert_empty decision['workflows']
  end

  def test_aliases_accept_name_file_and_declared_alias
    ['Swift Tests', 'swift-tests', 'swift'].each do |value|
      decision = resolve([comment('owner', 'MEMBER', "skip-#{value}")])

      assert_equal ['Swift Tests'], decision['workflows'], value
    end
  end

  def test_directive_is_case_insensitive
    decision = resolve([comment('owner', 'COLLABORATOR', 'Skip-Web')])

    assert_equal ['Web CI'], decision['workflows']
  end

  def test_fenced_and_quoted_directives_are_ignored
    body = <<~BODY
      > skip-all
      ```
      skip-all
      ```
      Leave CI alone.
    BODY
    decision = resolve([comment('owner', 'OWNER', body)])

    assert_empty decision['workflows']
  end

  def test_later_directives_override_earlier_ones
    decision = resolve(
      [
        comment('owner', 'OWNER', 'skip-all'),
        comment('owner', 'OWNER', 'unskip-web because the site changed')
      ]
    )

    assert_equal ['Swift Tests'], decision['workflows']
    assert_equal false, decision['skipAll']
  end

  def test_unskip_all_clears_every_skip
    decision = resolve([comment('owner', 'OWNER', 'skip-all'), comment('owner', 'OWNER', 'unskip-all')])

    assert_empty decision['workflows']
    assert_empty decision['checks']
    assert_equal false, decision['skipAll']
  end

  def test_unknown_alias_is_reported_without_selecting_anything
    decision = resolve([comment('owner', 'OWNER', 'skip-android')])

    assert_empty decision['workflows']
    assert_equal ['android'], decision['unknown']
  end

  def test_manifest_rejects_duplicate_and_reserved_aliases
    duplicate = { 'workflows' => [MANIFEST['workflows'][0], MANIFEST['workflows'][0]] }
    assert_raises(CiSkip::ManifestError) { CiSkip::Manifest.new(duplicate) }

    reserved = { 'workflows' => [MANIFEST['workflows'][0].merge('aliases' => ['all'])] }
    assert_raises(CiSkip::ManifestError) { CiSkip::Manifest.new(reserved) }
  end

  def test_manifest_requires_declared_checks
    without_checks = { 'workflows' => [MANIFEST['workflows'][0].merge('checks' => [])] }

    assert_raises(CiSkip::ManifestError) { CiSkip::Manifest.new(without_checks) }
  end

  def test_verifier_reports_missing_workflow_and_stale_check
    Dir.mktmpdir('ci-skip-verifier-test') do |directory|
      write_workflow(directory, 'swift-tests.yml', 'Swift Tests', ['Swift Tests', 'CodeQL (swift)'])
      write_workflow(directory, 'web-ci.yml', 'Web CI', ['Web Build & Test'])
      write_workflow(directory, 'extra.yml', 'Extra', ['Extra Job'])

      errors = CiSkip::ManifestVerifier.new(CiSkip::Manifest.new(MANIFEST), directory).run

      assert_includes errors.join("\n"), 'extra.yml: runs on pull_request but is missing from the manifest'
    end
  end

  def test_verifier_ignores_gate_jobs_and_expands_matrix_names
    Dir.mktmpdir('ci-skip-verifier-test') do |directory|
      File.write(
        File.join(directory, 'swift-tests.yml'),
        <<~YAML
          name: Swift Tests
          on:
            pull_request:
              branches: [main]
          jobs:
            gate:
              name: Skip Gate
              steps:
                - uses: ./.github/actions/ci-skip-gate
            test:
              name: Swift Tests
              steps: []
            matrix-job:
              name: CodeQL (${{ matrix.language }})
              steps: []
        YAML
      )
      write_workflow(directory, 'web-ci.yml', 'Web CI', ['Web Build & Test'])

      errors = CiSkip::ManifestVerifier.new(CiSkip::Manifest.new(MANIFEST), directory).run

      assert_empty errors, errors.join("\n")
    end
  end

  def test_repository_manifest_matches_its_workflows
    manifest = CiSkip::Manifest.load(File.expand_path('../ci-skip.json', __dir__))
    errors = CiSkip::ManifestVerifier.new(manifest, File.expand_path('../workflows', __dir__)).run

    assert_empty errors, errors.join("\n")
  end

  private

  def resolve(comments, reviewers: [])
    CiSkip::Resolver.new(CiSkip::Manifest.new(MANIFEST)).resolve(comments: comments, reviewers: reviewers)
  end

  def comment(login, association, body)
    { 'login' => login, 'association' => association, 'body' => body }
  end

  def write_workflow(directory, file, name, job_names)
    jobs = job_names.each_with_index.map { |job_name, index| "  job#{index}:\n    name: #{job_name}\n    steps: []" }.join("\n")
    File.write(
      File.join(directory, file),
      "name: #{name}\non:\n  pull_request:\n    branches: [main]\njobs:\n#{jobs}\n"
    )
  end
end
