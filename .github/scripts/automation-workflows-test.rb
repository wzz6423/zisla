#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'yaml'
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'

class AutomationWorkflowsTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @directory = Dir.mktmpdir('zisla-automation-workflows-')
    FileUtils.mkdir_p(File.join(@directory, 'bin'))
    FileUtils.mkdir_p(File.join(@directory, '.github'))
    FileUtils.mkdir_p(File.join(@directory, 'mac/Resources/Emoji'))
    File.write(File.join(@directory, '.github/project-automation.json'), JSON.generate(project: { owner: 'fixture-maintainer' }))
    File.write(File.join(@directory, 'mac/Resources/Emoji/EmojiNameAliases.json'), JSON.generate(emojiVersion: '17.0', cldrVersion: '48.0'))
    %w[gh git].each do |command|
      path = File.join(@directory, 'bin', command)
      File.write(path, <<~'SCRIPT')
        #!/usr/bin/env ruby
        require 'json'
        command = File.basename($PROGRAM_NAME)
        input = ARGV.include?('--input') ? STDIN.read : nil
        File.open(ENV.fetch('CAPTURE'), 'a') { |file| file.puts JSON.generate(command: command, args: ARGV, input: input) }
        if command == 'gh'
          exit ENV.fetch('API_EXIT', '0').to_i unless ENV.fetch('API_EXIT', '0') == '0'
          puts ENV.fetch('ASSIGNEE_COUNT', '0') if ARGV.first == 'api' && ARGV.include?('--jq')
        end
      SCRIPT
      File.chmod(0o755, path)
    end
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_emoji_creation_uses_an_event_triggering_token
    create = step('emoji-catalog-update', 'Create an update pull request')
    assert_equal '${{ secrets.PROJECT_AUTOMATION_TOKEN }}', create.fetch('env').fetch('GH_TOKEN')
    output, status = run_step(create, 'GH_TOKEN' => 'fixture-token')
    assert status.success?, output
    assert_equal 1, calls.count { |call| call['args'][0, 2] == %w[pr create] }
  end

  def test_missing_token_fails_before_any_repository_mutation
    output, status = run_step(step('emoji-catalog-update', 'Create an update pull request'), 'GH_TOKEN' => '')
    refute status.success?
    assert_includes output, 'PROJECT_AUTOMATION_TOKEN is required'
    assert_empty calls
  end

  def test_pr_creation_permission_failure_propagates
    _output, status = run_step(step('emoji-catalog-update', 'Create an update pull request'), 'API_EXIT' => '7')
    assert_equal 7, status.exitstatus
  end

  def test_human_author_is_assigned
    assert_assignment('contributor', 'contributor')
  end

  def test_bot_is_assigned_to_configured_maintainer
    assign = step('pr-automation', 'Ensure the pull request has an assignee')
    refute assign.key?('if'), 'Bot pull requests must reach the assignment step'
    assert_assignment('github-actions[bot]', 'fixture-maintainer')
  end

  def test_existing_assignment_is_preserved
    output, status = run_step(step('pr-automation', 'Ensure the pull request has an assignee'), 'ASSIGNEE_COUNT' => '1')
    assert status.success?, output
    assert_empty calls.select { |call| call['args'].include?('POST') }
  end

  def test_missing_bot_maintainer_fails_without_assignment
    File.write(File.join(@directory, '.github/project-automation.json'), '{"project":{}}')
    _output, status = run_step(step('pr-automation', 'Ensure the pull request has an assignee'), 'PR_AUTHOR' => 'dependabot[bot]')
    refute status.success?
    assert_empty calls.select { |call| call['args'].include?('POST') }
  end

  def test_assignment_api_failure_propagates
    _output, status = run_step(step('pr-automation', 'Ensure the pull request has an assignee'), 'API_EXIT' => '7')
    assert_equal 7, status.exitstatus
  end

  def test_web_codeql_excludes_only_generated_sparkle_relocation_maps
    workflow = YAML.load_file(File.join(ROOT, '.github/workflows/web-ci.yml'))
    initialization = workflow.fetch('jobs').fetch('codeql').fetch('steps').find do |entry|
      entry.fetch('uses', '').start_with?('github/codeql-action/init@')
    end
    config = YAML.load_file(File.join(ROOT, initialization.fetch('with').fetch('config-file')))
    assert_equal ['name', 'paths-ignore'], config.keys.sort
    patterns = config.fetch('paths-ignore')
    excluded = lambda { |path| patterns.any? { |pattern| File.fnmatch?(pattern, path, File::FNM_PATHNAME) } }
    maps = Dir.glob('mac/Vendor/Sparkle.xcframework/**/Relocations/**/*.yml', base: ROOT)
    refute_empty maps
    maps.each { |path| assert excluded.call(path), path }
    [
      'web/src/app.ts', '.github/workflows/web-ci.yml',
      'mac/Sources/ZislaKit/UpdateService.swift',
      'mac/Vendor/Sparkle.xcframework/macos-arm64_x86_64/config.yml',
      'mac/Vendor/Sparkle.xcframework/macos-arm64_x86_64/dSYMs/Sparkle.framework.dSYM/Contents/Resources/config.yml',
      'mac/Vendor/Other/Contents/Resources/Relocations/aarch64/config.yml'
    ].each { |path| refute excluded.call(path), path }
  end

  private

  def step(workflow, name)
    YAML.load_file(File.join(ROOT, '.github/workflows', "#{workflow}.yml"))
        .fetch('jobs').values.flat_map { |job| job.fetch('steps') }.find { |entry| entry['name'] == name } || raise(name)
  end

  def run_step(step, env = {})
    Open3.capture2e({
      'PATH' => "#{@directory}/bin:#{ENV.fetch('PATH')}",
      'CAPTURE' => File.join(@directory, 'calls.jsonl'),
      'RUNNER_TEMP' => @directory,
      'GITHUB_REPOSITORY' => 'fixture/repository',
      'GH_TOKEN' => 'fixture-token',
      'BRANCH' => 'automation/fixture',
      'DEFAULT_BRANCH' => 'main',
      'PR_AUTHOR' => 'contributor',
      'PR_NUMBER' => '153'
    }.merge(env), 'bash', '-c', step.fetch('run'), chdir: @directory)
  end

  def calls
    path = File.join(@directory, 'calls.jsonl')
    File.exist?(path) ? File.readlines(path).map { |line| JSON.parse(line) } : []
  end

  def assert_assignment(author, expected)
    output, status = run_step(step('pr-automation', 'Ensure the pull request has an assignee'), 'PR_AUTHOR' => author)
    assert status.success?, output
    mutations = calls.select { |call| call['args'].include?('POST') }
    assert_equal 1, mutations.length
    assert_equal({ 'assignees' => [expected] }, JSON.parse(mutations.first.fetch('input')))
  end
end
