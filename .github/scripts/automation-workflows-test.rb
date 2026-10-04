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
    assert_equal "github.event.action != 'closed'", assign.fetch('if')
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

  def test_windows_core_configurations_have_static_checks_when_skipped
    jobs = YAML.safe_load(File.read(File.join(ROOT, '.github/workflows/core-build.yml')), aliases: true).fetch('jobs')
    gate = "needs.gate.outputs.skip != 'true' && needs.gate.outputs.relevant != 'false'"
    %w[Debug Release].each do |configuration|
      job = jobs.fetch("core-#{configuration.downcase}")
      assert_equal "Windows Core (#{configuration})", job.fetch('name')
      assert_equal configuration, job.fetch('env').fetch('CONFIGURATION')
      assert_equal 'gate', job.fetch('needs')
      assert_equal gate, job.fetch('if')
      refute job.key?('strategy')
    end
    debug_steps = jobs.fetch('core-debug').fetch('steps')
    assert_equal debug_steps, jobs.fetch('core-release').fetch('steps')
    assert_includes debug_steps.find { |entry| entry['name'] == 'Configure, build, and test' }.fetch('run'),
                    '-DCMAKE_BUILD_TYPE=$env:CONFIGURATION'

    result = jobs.fetch('core-result')
    assert_equal 'Windows Core Tests', result.fetch('name')
    assert_equal %w[gate core-debug core-release], result.fetch('needs')
    assert_equal "always() && #{gate}", result.fetch('if')
    verification = result.fetch('steps').first
    assert_equal({ 'DEBUG_RESULT' => '${{ needs.core-debug.result }}',
                   'RELEASE_RESULT' => '${{ needs.core-release.result }}' }, verification.fetch('env'))
    %w[success failure cancelled skipped].product(%w[success failure cancelled skipped]).each do |debug, release|
      output, status = run_step(verification, 'DEBUG_RESULT' => debug, 'RELEASE_RESULT' => release)
      assert_equal debug == 'success' && release == 'success', status.success?,
                   "Debug=#{debug}, Release=#{release}: #{output}"
    end
  end

  def test_issue_timeline_tracks_close_and_reopen_without_losing_edits
    install_workflow_fixture
    event = workflow_event('issue', 'closed', closed_at: '2026-10-05T02:30:00Z')
    install_event(event, current_resource: event.fetch('issue').merge('body' => 'Latest user edit'))

    output, status = run_timeline_step('issue-automation', 'Synchronize issue timeline')
    assert status.success?, output
    body = JSON.parse(File.read(File.join(@directory, 'resource.json'))).fetch('body')
    assert_includes body, 'Latest user edit'
    assert_includes body, '- Ended: 2026-10-05 10:30:00 UTC+08:00'

    event['issue']['state'] = 'open'
    install_event(event, current_resource: event.fetch('issue').merge('body' => body))
    output, status = run_timeline_step('issue-automation', 'Synchronize issue timeline')
    assert status.success?, output
    body = JSON.parse(File.read(File.join(@directory, 'resource.json'))).fetch('body')
    refute_includes body, '- Ended:'
    assert_includes body, 'Latest user edit'

    output, status = run_timeline_step('issue-automation', 'Synchronize issue timeline')
    assert status.success?, output
    assert_equal 2, calls.count { |call| call['args'].include?('PATCH') }
  end

  def test_pull_request_timeline_uses_merge_time
    install_workflow_fixture
    event = workflow_event('pull_request', 'closed',
      closed_at: '2026-10-05T02:29:59Z', merged_at: '2026-10-05T02:30:00Z')
    install_event(event, current_resource: event.fetch('pull_request').merge('body' => 'Review body'))

    output, status = run_timeline_step('pr-automation', 'Synchronize pull request timeline')
    assert status.success?, output
    assert_includes JSON.parse(File.read(File.join(@directory, 'resource.json'))).fetch('body'),
                    '- Ended: 2026-10-05 10:30:00 UTC+08:00'
    assert calls.any? { |call| call['args'].include?('repos/fixture/repository/pulls/153') }
  end

  def test_timeline_read_failure_cannot_patch_the_body
    install_workflow_fixture
    install_event(workflow_event('issue', 'open'))

    _output, status = run_timeline_step('issue-automation', 'Synchronize issue timeline', 'GH_READ_EXIT' => '7')
    assert_equal 7, status.exitstatus
    assert_empty calls.select { |call| call['args'].include?('PATCH') }
  end

  def test_close_events_run_only_the_timeline_and_cleanup_steps
    {
      'issue-automation' => 'issues',
      'pr-automation' => 'pull_request_target'
    }.each do |workflow_name, trigger|
      workflow = YAML.load_file(File.join(ROOT, '.github/workflows', "#{workflow_name}.yml"))
      assert_includes workflow.fetch(true).fetch(trigger).fetch('types'), 'closed'
      steps = workflow.fetch('jobs').fetch('automate').fetch('steps')
      assert_equal 'checkout', steps.first.fetch('id')
      timeline = steps.find { |entry| entry.fetch('name', '').match?(/Synchronize .* timeline/) }
      assert_equal "${{ !cancelled() && steps.checkout.outcome == 'success' }}", timeline.fetch('if')
      skipped = steps.select { |entry| entry['name'] && entry['name'] !~ /Synchronize .* timeline|Remove .* metadata files/ }
      skipped.each do |entry|
        assert_equal "github.event.action != 'closed'", entry.fetch('if'), entry.fetch('name')
      end
    end
  end

  def test_project_workflow_writes_dates_for_open_closed_merge_and_reopen
    install_workflow_fixture
    install_project_fields
    cases = [
      [workflow_event('issue', 'open'), '2026-10-04', nil],
      [workflow_event('issue', 'closed', closed_at: '2026-10-05T02:30:00Z'), '2026-10-04', '2026-10-05'],
      [workflow_event('pull_request', 'closed', closed_at: '2026-10-05T02:29:59Z',
        merged_at: '2026-10-05T02:30:00Z'), '2026-10-04', '2026-10-05'],
      [workflow_event('issue', 'open'), '2026-10-04', nil]
    ]

    cases.each do |event, submitted, ended|
      install_event(event)
      File.write(File.join(@directory, 'calls.jsonl'), '')
      output, status = run_project_step
      assert status.success?, output
      updates = graphql_calls('updateProjectV2ItemFieldValue')
      assert updates.any? { |call| call['args'].include?("date=#{submitted}") && call['args'].include?('fieldId=submitted-id') }
      if ended
        assert updates.any? { |call| call['args'].include?("date=#{ended}") && call['args'].include?('fieldId=ended-id') }
        assert_empty graphql_calls('clearProjectV2ItemFieldValue')
      else
        assert graphql_calls('clearProjectV2ItemFieldValue').any? { |call| call['args'].include?('fieldId=ended-id') }
      end
    end
  end

  def test_project_workflow_uses_current_state_when_an_old_event_is_replayed
    install_workflow_fixture
    install_project_fields
    %w[issue pull_request].product(%w[open closed]).each do |kind, state|
      old_state = state == 'open' ? 'closed' : 'open'
      event = workflow_event(kind, old_state, closed_at: '2026-10-05T02:30:00Z')
      current = workflow_event(kind, state, closed_at: '2026-10-06T02:30:00Z').fetch(kind)
      install_event(event, current_resource: current)
      File.write(File.join(@directory, 'calls.jsonl'), '')

      output, status = run_project_step
      assert status.success?, output
      updates = graphql_calls('updateProjectV2ItemFieldValue')
      if state == 'closed'
        assert updates.any? { |call| call['args'].include?('date=2026-10-06') && call['args'].include?('fieldId=ended-id') }
        assert updates.any? { |call| call['args'].include?('optionId=done-id') }
      else
        refute updates.any? { |call| call['args'].include?('fieldId=ended-id') }
        assert graphql_calls('clearProjectV2ItemFieldValue').any? { |call| call['args'].include?('fieldId=ended-id') }
      end
    end
  end

  def test_project_resource_read_failure_cannot_mutate_the_project
    install_workflow_fixture
    install_project_fields
    install_event(workflow_event('issue', 'open'))

    _output, status = run_project_step('GH_READ_EXIT' => '7')
    assert_equal 7, status.exitstatus
    assert_empty calls.select { |call| call['args'].include?('graphql') }
  end

  def test_project_workflow_creates_missing_date_fields
    install_workflow_fixture
    install_project_fields([])
    install_event(workflow_event('issue', 'open'))

    output, status = run_project_step
    assert status.success?, output
    assert_equal 2, graphql_calls('createProjectV2Field').length
    assert_equal %w[End\ date Submitted\ date],
                 JSON.parse(File.read(File.join(@directory, 'fields.json'))).map { |field| field['name'] }.sort
  end

  def test_project_workflow_accepts_a_concurrent_field_creation
    install_workflow_fixture
    install_project_fields([])
    install_event(workflow_event('issue', 'open'))

    output, status = run_project_step('CREATE_MODE' => 'race')
    assert status.success?, output
    assert_equal 2, graphql_calls('createProjectV2Field').length
  end

  def test_project_workflow_rejects_wrong_field_type_before_item_mutations
    install_workflow_fixture
    install_project_fields([{ 'id' => 'wrong-id', 'name' => 'Submitted date', 'dataType' => 'TEXT' }])
    install_event(workflow_event('issue', 'open'))

    output, status = run_project_step
    refute status.success?
    assert_includes output, 'not a DATE field'
    assert_empty graphql_calls('updateProjectV2ItemFieldValue')
  end

  def test_project_workflow_propagates_field_creation_permission_failure
    install_workflow_fixture
    install_project_fields([])
    install_event(workflow_event('issue', 'open'))

    output, status = run_project_step('CREATE_MODE' => 'permission')
    refute status.success?
    assert_includes output, 'Could not create the DATE field'
    assert_empty graphql_calls('updateProjectV2ItemFieldValue')
  end

  def test_project_workflow_propagates_date_graphql_error
    install_workflow_fixture
    install_project_fields
    install_event(workflow_event('issue', 'closed', closed_at: '2026-10-05T02:30:00Z'))

    output, status = run_project_step('GH_MUTATION_ERROR' => 'date')
    refute status.success?
    assert_includes output, 'date mutation rejected'
  end

  def test_project_workflow_stops_on_project_query_graphql_error
    install_workflow_fixture
    install_project_fields
    install_event(workflow_event('issue', 'open'))

    output, status = run_project_step('GH_READ_ERROR' => '1')
    refute status.success?
    assert_includes output, 'project query rejected'
    assert_empty graphql_calls('updateProjectV2ItemFieldValue')
  end

  def test_project_workflow_stops_on_field_creation_graphql_error
    install_workflow_fixture
    install_project_fields([])
    install_event(workflow_event('issue', 'open'))

    output, status = run_project_step('CREATE_MODE' => 'graphql_error')
    refute status.success?
    assert_includes output, 'Could not create the DATE field'
    assert_empty graphql_calls('updateProjectV2ItemFieldValue')
  end

  private

  def install_workflow_fixture
    FileUtils.mkdir_p(File.join(@directory, '.github/scripts'))
    %w[project-metadata.rb pr-metadata.rb timeline-metadata.rb].each do |name|
      FileUtils.cp(File.join(ROOT, '.github/scripts', name), File.join(@directory, '.github/scripts', name))
    end
    FileUtils.cp(File.join(ROOT, '.github/project-automation.json'), File.join(@directory, '.github/project-automation.json'))
    FileUtils.cp(File.join(ROOT, '.github/pr-automation.json'), File.join(@directory, '.github/pr-automation.json'))
    File.write(File.join(@directory, 'bin/gh'), <<~'SCRIPT')
      #!/usr/bin/env ruby
      require 'json'
      input = ARGV.include?('--input') ? File.read(ARGV[ARGV.index('--input') + 1]) : nil
      File.open(ENV.fetch('CAPTURE'), 'a') { |file| file.puts JSON.generate(args: ARGV, input: input) }
      if ARGV.include?('graphql')
        query = ARGV.find { |arg| arg.start_with?('query=') }.to_s
        fields = JSON.parse(File.read(ENV.fetch('FIELD_STATE')))
        case query
        when /query\(\$login:/
          if ENV['GH_READ_ERROR'] == '1'
            puts JSON.generate(errors: [{ message: 'project query rejected' }])
            exit
          end
          status = { id: 'status-id', name: 'Status', options: [
            { id: 'inbox-id', name: 'Inbox' }, { id: 'done-id', name: 'Done' }
          ] }
          puts JSON.generate(data: { user: { projectV2: {
            id: 'project-id', title: 'zisla Development', fields: { nodes: [status, *fields] }
          } } })
        when /query\(\$projectId:/
          puts JSON.generate([{ data: { node: { items: { nodes: [
            { id: 'item-id', content: { id: 'content-id' } }
          ], pageInfo: { hasNextPage: false, endCursor: nil } } } } }])
        when /createProjectV2Field/
          mode = ENV.fetch('CREATE_MODE', 'success')
          if mode == 'graphql_error'
            puts JSON.generate(errors: [{ message: 'field creation rejected' }])
            exit
          end
          if mode == 'permission'
            warn 'permission denied'
            exit 7
          end
          name = ARGV.find { |arg| arg.start_with?('name=') }.delete_prefix('name=')
          fields << { 'id' => name == 'Submitted date' ? 'submitted-id' : 'ended-id',
                      'name' => name, 'dataType' => 'DATE' }
          File.write(ENV.fetch('FIELD_STATE'), JSON.generate(fields))
          if mode == 'race'
            warn 'field already exists'
            exit 7
          end
          puts JSON.generate(data: { createProjectV2Field: { projectV2Field: { id: fields.last['id'] } } })
        when /updateProjectV2ItemFieldValue/
          if ENV['GH_MUTATION_ERROR'] == 'date' && ARGV.any? { |arg| arg.start_with?('date=') }
            puts JSON.generate(errors: [{ message: 'date mutation rejected' }])
          else
            puts JSON.generate(data: { updateProjectV2ItemFieldValue: { projectV2Item: { id: 'item-id' } } })
          end
        when /clearProjectV2ItemFieldValue/
          puts JSON.generate(data: { clearProjectV2ItemFieldValue: { projectV2Item: { id: 'item-id' } } })
        else
          warn "Unexpected GraphQL query: #{query}"
          exit 8
        end
      elsif ARGV.include?('PATCH')
        resource = JSON.parse(File.read(ENV.fetch('RESOURCE_PATH')))
        File.write(ENV.fetch('RESOURCE_PATH'), JSON.generate(resource.merge(JSON.parse(input))))
        puts '{}'
      else
        exit ENV.fetch('GH_READ_EXIT', '0').to_i unless ENV.fetch('GH_READ_EXIT', '0') == '0'
        puts File.read(ENV.fetch('RESOURCE_PATH'))
      end
    SCRIPT
    File.chmod(0o755, File.join(@directory, 'bin/gh'))
  end

  def install_project_fields(fields = [
    { 'id' => 'submitted-id', 'name' => 'Submitted date', 'dataType' => 'DATE' },
    { 'id' => 'ended-id', 'name' => 'End date', 'dataType' => 'DATE' }
  ])
    File.write(File.join(@directory, 'fields.json'), JSON.generate(fields))
  end

  def workflow_event(kind, state, closed_at: nil, merged_at: nil)
    { kind => { 'node_id' => 'content-id', 'number' => 153, 'body' => '', 'labels' => [],
                'state' => state, 'created_at' => '2026-10-03T16:30:00Z',
                'closed_at' => closed_at, 'merged_at' => merged_at } }
  end

  def install_event(event, current_resource: event.values.first)
    File.write(File.join(@directory, 'event.json'), JSON.generate(event))
    File.write(File.join(@directory, 'resource.json'), JSON.generate(current_resource))
  end

  def run_timeline_step(workflow, name, env = {})
    run_step(step(workflow, name), {
      'GITHUB_EVENT_PATH' => File.join(@directory, 'event.json'),
      'RESOURCE_PATH' => File.join(@directory, 'resource.json'),
      'ISSUE_NUMBER' => '153', 'PR_NUMBER' => '153'
    }.merge(env))
  end

  def run_project_step(env = {})
    run_step(step('project-automation', 'Add item and synchronize status'), {
      'GITHUB_EVENT_PATH' => File.join(@directory, 'event.json'),
      'RESOURCE_PATH' => File.join(@directory, 'resource.json'),
      'FIELD_STATE' => File.join(@directory, 'fields.json'),
      'PROJECT_TOKEN' => 'fixture-token'
    }.merge(env))
  end

  def graphql_calls(operation)
    calls.select do |call|
      call['args'].include?('graphql') && call['args'].any? { |arg| arg.start_with?('query=') && arg.include?(operation) }
    end
  end

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
