#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'

# Parses and validates the pull request body contract.
#
# The body must declare its change type, its related issue and whether an AI
# agent co-authored the change, so that the PR Automation workflow can apply the
# matching labels and enforce co-author attribution without guessing.
module PullRequestMetadata
  CLOSING_KEYWORD = /(?:closes|closed|close|fixes|fixed|fix|resolves|resolved|resolve)/i
  ISSUE_REFERENCE = /#{CLOSING_KEYWORD}[[:space:]]+(?:[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+)?#(\d+)/
  ISSUE_URL = %r{#{CLOSING_KEYWORD}[[:space:]]+https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/issues/(\d+)}
  COAUTHOR_TRAILER = /\A[^<>]+<[^<>@[:space:]]+@[^<>[:space:]]+>\z/
  PLACEHOLDER = /\A<!--/
  # Nothing inside a template comment is visible in the rendered body, so it
  # must never be parsed: the shipped template documents `Closes #123`, which
  # would otherwise link that issue and contradict the `None` above it.
  COMMENT = /<!--.*?-->/m
  REQUIRED_SECTIONS = ['Summary', 'GitHub Project', 'PR Type', 'Validation', 'Risk and Rollback', 'Related Issue', 'AI Attribution'].freeze

  class ContractError < StandardError; end

  # The label contract shared with .github/pr-automation.json.
  class Contract
    def self.load(path)
      new(JSON.parse(File.read(path)))
    rescue JSON::ParserError => error
      raise ContractError, "#{path}: invalid JSON (#{error.message})"
    end

    def initialize(document)
      @types = Array(document['types'])
      raise ContractError, 'contract declares no types' if @types.empty?

      @project = document.fetch('project')
      @issue_label = document.fetch('issueLabel')
      @ai_label = document.fetch('aiLabel')
      @skip_label = document.fetch('skipLabel')
    end

    def type_names
      @types.map { |entry| entry['type'] }
    end

    def project_name
      @project.fetch('name')
    end

    def label_for(type)
      entry = @types.find { |candidate| candidate['type'] == type }
      entry && entry['label']
    end

    def type_labels
      @types.map { |entry| entry['label'] }.uniq
    end

    def issue_label
      @issue_label['label']
    end

    def ai_label
      @ai_label['label']
    end

    def managed_labels
      (@types + [@issue_label, @ai_label, @skip_label]).uniq { |entry| entry['label'] }
    end
  end

  def self.sections(body)
    current = nil
    body.to_s.gsub("\r\n", "\n").gsub(COMMENT, '').each_line.each_with_object({}) do |raw_line, map|
      line = raw_line.chomp
      heading = line.match(/\A##[[:space:]]+(.+?)[[:space:]]*\z/)
      if heading
        current = heading[1]
        map[current] ||= []
      elsif current
        map[current] << line
      end
    end
  end

  # Returns every `- Key: value` value in a section, dropping template comments.
  def self.field_values(lines, key)
    pattern = /\A[[:space:]]*-[[:space:]]*#{Regexp.escape(key)}:[[:space:]]*(.*?)[[:space:]]*\z/i
    Array(lines).filter_map do |line|
      match = pattern.match(line)
      next if match.nil?

      value = match[1].to_s
      next if value.empty? || PLACEHOLDER.match?(value)

      value
    end
  end

  def self.field(lines, key)
    field_values(lines, key).first
  end

  def self.parse(body, contract)
    parsed = sections(body)
    type = field(parsed['PR Type'], 'Type')
    agent = field(parsed['AI Attribution'], 'Agent')
    agent = nil if agent.to_s.casecmp('none').zero?
    related = Array(parsed['Related Issue']).join("\n")

    {
      'type' => type,
      'typeLabel' => type && contract.label_for(type),
      'project' => field(parsed['GitHub Project'], 'Project'),
      'issues' => (related.scan(ISSUE_REFERENCE) + related.scan(ISSUE_URL)).flatten.map(&:to_i).uniq.sort,
      'relatedIsNone' => Array(parsed['Related Issue']).any? { |line| line.match?(/\A[[:space:]]*-?[[:space:]]*none[[:space:]]*\z/i) },
      'agent' => agent,
      'agentRaw' => field(parsed['AI Attribution'], 'Agent'),
      'coAuthors' => field_values(parsed['AI Attribution'], 'Co-authored-by'),
      'sections' => parsed
    }
  end

  def self.title_pattern(contract)
    types = contract.type_names.map { |type| Regexp.escape(type) }.join('|')
    /\A(#{types})(?:\([a-z0-9][a-z0-9-]*\))?!?: [ -~]+\z/
  end

  def self.labels(metadata, contract)
    labels = [metadata['typeLabel']].compact
    labels << contract.issue_label unless Array(metadata['issues']).empty?
    labels << contract.ai_label if metadata['agent']
    labels.uniq
  end

  def self.validate(title:, body:, contract:)
    errors = []
    title_match = title_pattern(contract).match(title.to_s.strip)
    unless title_match
      errors << 'Title must be an English Conventional Commit subject, for example "feat(ci): add pull request automation".'
      errors << "Allowed types: #{contract.type_names.join(', ')}."
    end

    metadata = parse(body, contract)
    missing = REQUIRED_SECTIONS.reject { |section| metadata['sections'].key?(section) }
    errors << "Missing required section(s): #{missing.map { |section| "## #{section}" }.join(', ')}." unless missing.empty?

    errors.concat(validate_type(metadata, contract, title_match))
    errors.concat(validate_project(metadata, contract))
    errors.concat(validate_validation(metadata))
    errors.concat(validate_related_issue(metadata))
    errors.concat(validate_attribution(metadata))
    errors
  end

  def self.validate_type(metadata, contract, title_match)
    values = field_values(metadata['sections']['PR Type'], 'Type')
    return ['PR Type must declare exactly one "- Type: <type>" entry.'] unless values.length == 1

    type = values.first
    unless contract.type_names.include?(type)
      return ["PR Type #{type.inspect} is not allowed. Use one of: #{contract.type_names.join(', ')}."]
    end

    return [] if title_match.nil? || title_match[1] == type

    ["PR Type #{type.inspect} does not match the title type #{title_match[1].inspect}."]
  end

  def self.validate_project(metadata, contract)
    lines = metadata['sections']['GitHub Project']
    return [] if lines.nil?

    values = field_values(lines, 'Project')
    return ['GitHub Project must declare exactly one "- Project: zisla Development" entry.'] unless values.length == 1
    return [] if values.first == contract.project_name

    ["GitHub Project must be #{contract.project_name.inspect}."]
  end

  def self.validate_validation(metadata)
    lines = metadata['sections']['Validation']
    return [] if lines.nil?

    status = field(lines, 'Status')
    unless ['passed', 'failed', 'not run'].include?(status)
      return ['Validation must declare one exact status: passed, failed, or not run.']
    end

    required = status == 'not run' ? ['Reason'] : %w[Command Result]
    required.filter_map do |key|
      "Validation must include a non-empty #{key} field." if field(lines, key).nil?
    end
  end

  def self.validate_related_issue(metadata)
    return [] if metadata['sections']['Related Issue'].nil?

    has_issue = !Array(metadata['issues']).empty?
    return ['Related Issue must use a closing keyword such as "Closes #123", or exactly "None".'] unless has_issue || metadata['relatedIsNone']
    return ['Related Issue cannot be both "None" and a closing reference.'] if has_issue && metadata['relatedIsNone']

    []
  end

  def self.validate_attribution(metadata)
    return [] if metadata['sections']['AI Attribution'].nil?

    if metadata['agentRaw'].nil?
      return ['AI Attribution must declare "- Agent: <name>", or "- Agent: None" for a fully human-authored change.']
    end

    co_authors = Array(metadata['coAuthors'])
    if metadata['agent'].nil?
      return co_authors.empty? ? [] : ['AI Attribution declares Agent: None but still lists a Co-authored-by trailer.']
    end

    return ['AI Attribution must list at least one "- Co-authored-by: Name <email>" trailer for the declared agent.'] if co_authors.empty?

    co_authors.reject { |value| COAUTHOR_TRAILER.match?(value) }
              .map { |value| "Co-authored-by trailer #{value.inspect} must use the \"Name <email>\" form." }
  end
end

def command_validate(options, contract)
  errors = PullRequestMetadata.validate(
    title: File.read(options[:title_file]),
    body: File.read(options[:body_file]),
    contract: contract
  )
  if errors.empty?
    puts 'Pull request metadata is valid.'
    return
  end

  errors.each { |error| warn error }
  warn 'See CONTRIBUTING.md and .github/PULL_REQUEST_TEMPLATE.md for the required body sections.'
  exit 1
end

def command_json(options, contract)
  metadata = PullRequestMetadata.parse(File.read(options[:body_file]), contract)
  puts JSON.pretty_generate(
    'type' => metadata['type'],
    'typeLabel' => metadata['typeLabel'],
    'project' => metadata['project'],
    'issues' => metadata['issues'],
    'agent' => metadata['agent'],
    'coAuthors' => metadata['coAuthors'],
    'labels' => PullRequestMetadata.labels(metadata, contract),
    'managedLabels' => contract.type_labels + [contract.issue_label, contract.ai_label]
  )
end

if $PROGRAM_NAME == __FILE__
  options = { manifest: File.expand_path('../pr-automation.json', __dir__) }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: pr-metadata.rb <validate|json|labels> [options]'
    opts.on('--manifest PATH', 'Label contract path') { |value| options[:manifest] = value }
    opts.on('--title-file PATH', 'File holding the pull request title') { |value| options[:title_file] = value }
    opts.on('--body-file PATH', 'File holding the pull request body') { |value| options[:body_file] = value }
  end

  argv = parser.parse(ARGV)
  command = argv.shift

  begin
    contract = PullRequestMetadata::Contract.load(options[:manifest])
    case command
    when 'validate' then command_validate(options, contract)
    when 'json' then command_json(options, contract)
    when 'labels' then puts JSON.pretty_generate(contract.managed_labels)
    else
      warn parser.banner
      exit 1
    end
  rescue PullRequestMetadata::ContractError, KeyError, Errno::ENOENT, JSON::ParserError, TypeError => error
    warn error.message
    exit 1
  end
end
