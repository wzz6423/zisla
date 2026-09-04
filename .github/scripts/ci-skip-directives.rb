#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'set'
require 'time'
require 'yaml'

# Resolves CI skip directives written in pull request comments.
#
# A directive is the first token on a line and may be followed by free text:
#   skip-all            skip every pull request workflow
#   skip-web-ci         skip one workflow by name, file name or alias
#   skip-Web CI         the name may be written the way GitHub displays it
#   unskip-all          clear every skip
#   unskip-web-ci       clear one skip
#
# Directives are applied in comment order, so a later directive overrides an
# earlier one. Only comments from OWNER, MEMBER or COLLABORATOR authors and from
# requested reviewers count: anyone can submit a review on a public repository,
# but only accounts with write access can request one.
#
# A directive expires as soon as a newer commit reaches the pull request. It can
# only speak about the code its author had seen, and a skipped check satisfies a
# required status check, so an indefinitely sticky `skip-all` would let arbitrary
# later commits merge without ever being built.
module CiSkip
  AUTHORIZED_ASSOCIATIONS = %w[OWNER MEMBER COLLABORATOR].freeze
  RESERVED_ALIAS = 'all'
  DIRECTIVE_LINE = /\A[[:space:]]*((?:un)?skip)-([A-Za-z0-9].*)\z/i
  NOTE_SEPARATOR = /[[:space:]]*[:,;!][[:space:]]*/
  FENCE_LINE = /\A[[:space:]]{0,3}(?:```|~~~)/
  QUOTE_LINE = /\A[[:space:]]*>/
  GATE_ACTION = '.github/actions/ci-skip-gate'

  class ManifestError < StandardError; end

  # `since` is the committer date of the pull request head. A comment written
  # before that commit existed cannot have been about it, so its directives are
  # dropped instead of being replayed onto code nobody has looked at. A timestamp
  # that is missing or unreadable expires too: losing a directive only costs a
  # redundant CI run, while keeping one alive lets unbuilt code merge.
  def self.expired?(comment, since)
    return false if since.nil?

    Time.parse((comment['created_at'] || comment['createdAt']).to_s) < since
  rescue ArgumentError, TypeError
    true
  end

  def self.normalize(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
  end

  # Matches one manifest path pattern against one changed file. A pattern ending
  # in `/**` covers a whole directory tree; anything else is a plain fnmatch so a
  # single file such as `Makefile` can be scoped too. The comparison ignores case
  # because a directory renamed between `Web/` and `web/` must never silently
  # disable a required check while a branch still carries the other spelling.
  def self.path_match?(pattern, path)
    pattern = pattern.to_s
    if pattern.end_with?('/**')
      path.to_s.downcase.start_with?(pattern.delete_suffix('**').downcase)
    else
      File.fnmatch?(pattern, path.to_s, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_CASEFOLD)
    end
  end

  # Extracts directives from one comment body, ignoring fenced code blocks and
  # quoted lines so that quoting or documenting a directive never triggers it.
  def self.directives(body)
    inside_fence = false
    body.to_s.each_line.each_with_object([]) do |raw_line, found|
      line = raw_line.chomp
      if FENCE_LINE.match?(line)
        inside_fence = !inside_fence
        next
      end
      next if inside_fence || QUOTE_LINE.match?(line)

      match = DIRECTIVE_LINE.match(line)
      next unless match

      found << { 'negated' => match[1].casecmp('unskip').zero?, 'remainder' => match[2].strip }
    end
  end

  # The set of skippable workflows and the check names each one publishes.
  class Manifest
    attr_reader :workflows

    def self.load(path)
      new(JSON.parse(File.read(path)))
    rescue JSON::ParserError => error
      raise ManifestError, "#{path}: invalid JSON (#{error.message})"
    end

    def initialize(document)
      @workflows = Array(document['workflows'])
      raise ManifestError, 'manifest declares no workflows' if @workflows.empty?

      @alias_map = build_alias_map
      validate_paths!
    end

    def names
      workflows.map { |workflow| workflow['name'] }
    end

    def resolve_alias(value)
      @alias_map[CiSkip.normalize(value)]
    end

    # A maintainer writes the target the way GitHub displays it, so it may carry
    # spaces. The longest known target wins and the words it leaves become the
    # note, which keeps `skip-Web CI nothing to build` unambiguous.
    def split_remainder(remainder)
      head, _, tail = remainder.partition(NOTE_SEPARATOR)
      words = head.split(/[[:space:]]+/)
      words.length.downto(1) do |count|
        requested = CiSkip.normalize(words.take(count).join('-'))
        next unless requested == RESERVED_ALIAS || @alias_map.key?(requested)

        return [requested, note_from(words.drop(count), tail)]
      end

      [CiSkip.normalize(words.first), note_from(words.drop(1), tail)]
    end

    def aliases_for(name)
      @alias_map.select { |_, workflow| workflow == name }.keys.sort
    end

    # A workflow that declares no paths always runs. One that declares them only
    # runs when the pull request touches a matching file, which keeps a
    # documentation-only change from booting a Windows or macOS runner. An empty
    # file list means the caller could not read the change set, so the workflow
    # runs rather than silently reporting a check nobody verified.
    def relevant?(name, files)
      workflow = find(name)
      raise ManifestError, "unknown workflow #{name.inspect}" unless workflow

      patterns = Array(workflow['paths'])
      changed = Array(files)
      return true if patterns.empty? || changed.empty?

      changed.any? { |file| patterns.any? { |pattern| CiSkip.path_match?(pattern, file) } }
    end

    def checks_for(names)
      workflows.select { |workflow| names.include?(workflow['name']) }
               .flat_map { |workflow| Array(workflow['checks']) }
    end

    def find(name)
      workflows.find { |workflow| workflow['name'] == name }
    end

    private

    def validate_paths!
      workflows.each do |workflow|
        next unless workflow.key?('paths')

        patterns = workflow['paths']
        valid = patterns.is_a?(Array) && !patterns.empty? &&
                patterns.all? { |pattern| pattern.is_a?(String) && !pattern.strip.empty? }
        raise ManifestError, "#{workflow['name']}: paths must be a non-empty array of strings" unless valid
      end
    end

    def note_from(words, tail)
      (words + [tail]).reject(&:empty?).join(' ').strip
    end

    def build_alias_map
      workflows.each_with_object({}) do |workflow, map|
        name = workflow['name'].to_s
        file = workflow['file'].to_s
        raise ManifestError, 'every workflow needs a name and a file' if name.empty? || file.empty?
        raise ManifestError, "#{name}: declares no checks" if Array(workflow['checks']).empty?

        candidates = [name, File.basename(file, '.*')] + Array(workflow['aliases'])
        candidates.map { |candidate| CiSkip.normalize(candidate) }.uniq.each do |candidate|
          raise ManifestError, "#{name}: alias '#{candidate}' is reserved" if candidate == RESERVED_ALIAS
          raise ManifestError, "#{name}: alias '#{candidate}' already maps to #{map[candidate]}" if map.key?(candidate)

          map[candidate] = name
        end
      end
    end
  end

  # Replays the directives found in a comment thread into a final decision.
  class Resolver
    def initialize(manifest)
      @manifest = manifest
    end

    def resolve(comments:, reviewers: [], since: nil)
      reviewer_set = Array(reviewers).map { |login| login.to_s.downcase }.to_set
      state = { selected: Set.new, skip_all: false, unknown: [], applied: [], expired: [] }

      Array(comments).each do |comment|
        next unless authorized?(comment, reviewer_set)

        expired = CiSkip.expired?(comment, since)
        CiSkip.directives(comment['body']).each do |directive|
          next apply(state, comment, directive) unless expired

          requested, note = @manifest.split_remainder(directive['remainder'])
          state[:expired] << entry(comment, directive['negated'], requested, note)
        end
      end

      selected = @manifest.names.select { |name| state[:selected].include?(name) }
      {
        'skipAll' => state[:skip_all],
        'workflows' => selected,
        'checks' => @manifest.checks_for(selected),
        'unknown' => state[:unknown],
        'directives' => state[:applied],
        'expired' => state[:expired]
      }
    end

    private

    def authorized?(comment, reviewer_set)
      login = comment['login'].to_s
      return false if login.empty? || login.end_with?('[bot]')

      AUTHORIZED_ASSOCIATIONS.include?(comment['association'].to_s.upcase) ||
        reviewer_set.include?(login.downcase)
    end

    def apply(state, comment, directive)
      negated = directive['negated']
      requested, note = @manifest.split_remainder(directive['remainder'])

      if requested == RESERVED_ALIAS
        state[:skip_all] = !negated
        negated ? state[:selected].clear : state[:selected].merge(@manifest.names)
      else
        name = @manifest.resolve_alias(requested)
        unless name
          state[:unknown] << requested unless state[:unknown].include?(requested)
          return
        end

        state[:skip_all] = false if negated
        negated ? state[:selected].delete(name) : state[:selected].add(name)
      end

      state[:applied] << entry(comment, negated, requested, note)
    end

    def entry(comment, negated, requested, note)
      {
        'login' => comment['login'].to_s,
        'directive' => "#{negated ? 'unskip' : 'skip'}-#{requested}",
        'note' => note
      }
    end
  end

  # Fails when the manifest drifts from the workflow files it describes.
  class ManifestVerifier
    def initialize(manifest, workflows_directory)
      @manifest = manifest
      @workflows_directory = workflows_directory
    end

    def run
      errors = []
      Dir.glob(File.join(@workflows_directory, '*.yml')).sort.each do |path|
        document = YAML.safe_load(File.read(path), aliases: true)
        basename = File.basename(path)
        next unless pull_request_triggered?(document)

        entry = @manifest.workflows.find { |workflow| workflow['file'] == basename }
        unless entry
          errors << "#{basename}: runs on pull_request but is missing from the manifest"
          next
        end

        errors.concat(verify_entry(entry, basename, document))
      end

      @manifest.workflows.each do |workflow|
        path = File.join(@workflows_directory, workflow['file'].to_s)
        errors << "#{workflow['name']}: file #{workflow['file']} does not exist" unless File.file?(path)
      end

      errors
    end

    private

    def pull_request_triggered?(document)
      # Psych parses the bare `on` key as the boolean true.
      triggers = document.is_a?(Hash) ? (document['on'] || document[true]) : nil
      case triggers
      when Hash then triggers.key?('pull_request')
      when Array then triggers.include?('pull_request')
      else triggers == 'pull_request'
      end
    end

    def verify_entry(entry, basename, document)
      errors = []
      declared = Array(entry['checks'])
      errors << "#{basename}: manifest name #{entry['name'].inspect} does not match #{document['name'].inspect}" if entry['name'] != document['name']

      job_names = displayed_job_names(document)
      job_names.reject { |name| name.include?('${{') }.each do |name|
        errors << "#{basename}: job #{name.inspect} is missing from the manifest checks" unless declared.include?(name)
      end

      matchers = job_names.map { |name| job_matcher(name) }
      declared.each do |check|
        errors << "#{basename}: manifest check #{check.inspect} matches no job" unless matchers.any? { |matcher| matcher.match?(check) }
      end

      errors
    end

    def displayed_job_names(document)
      Hash(document['jobs']).reject { |_, job| gate_job?(job) }
                            .map { |id, job| job.is_a?(Hash) ? (job['name'] || id) : id }
    end

    def gate_job?(job)
      return false unless job.is_a?(Hash)

      Array(job['steps']).any? { |step| step.is_a?(Hash) && step['uses'].to_s.include?(GATE_ACTION) }
    end

    def job_matcher(name)
      /\A#{name.split(/\$\{\{[^}]*\}\}/, -1).map { |part| Regexp.escape(part) }.join('.+')}\z/
    end
  end
end

def read_json(path, fallback)
  return fallback if path.nil?

  JSON.parse(File.read(path))
end

def parse_since(value)
  return nil if value.nil? || value.to_s.strip.empty?

  Time.parse(value.to_s)
rescue ArgumentError
  raise CiSkip::ManifestError, "invalid --since timestamp #{value.inspect}"
end

def command_resolve(options)
  manifest = CiSkip::Manifest.load(options[:manifest])
  decision = CiSkip::Resolver.new(manifest).resolve(
    comments: read_json(options[:comments], []),
    reviewers: read_json(options[:reviewers], []),
    since: parse_since(options[:since])
  )

  target = options[:for]
  if target
    raise CiSkip::ManifestError, "unknown workflow #{target.inspect}" unless manifest.find(target)

    puts decision['workflows'].include?(target) ? 'true' : 'false'
  else
    puts JSON.pretty_generate(decision)
  end
end

def command_relevant(options)
  manifest = CiSkip::Manifest.load(options[:manifest])
  target = options[:for]
  raise CiSkip::ManifestError, 'relevant requires --for NAME' unless target

  puts manifest.relevant?(target, read_json(options[:files], [])) ? 'true' : 'false'
end

def command_verify_manifest(options)
  manifest = CiSkip::Manifest.load(options[:manifest])
  errors = CiSkip::ManifestVerifier.new(manifest, options[:workflows]).run
  errors.each { |error| warn error }
  raise CiSkip::ManifestError, "manifest verification failed with #{errors.length} error(s)" unless errors.empty?

  puts "Verified #{manifest.workflows.length} skippable workflow(s)."
end

if $PROGRAM_NAME == __FILE__
  options = {
    manifest: File.expand_path('../ci-skip.json', __dir__),
    workflows: File.expand_path('../workflows', __dir__)
  }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ci-skip-directives.rb <resolve|relevant|verify-manifest> [options]'
    opts.on('--manifest PATH', 'Skip manifest path') { |value| options[:manifest] = value }
    opts.on('--comments PATH', 'JSON array of {login, association, body, created_at}') { |value| options[:comments] = value }
    opts.on('--since TIMESTAMP', 'Head commit date; older directives expire') { |value| options[:since] = value }
    opts.on('--reviewers PATH', 'JSON array of requested reviewer logins') { |value| options[:reviewers] = value }
    opts.on('--workflows PATH', 'Workflow directory') { |value| options[:workflows] = value }
    opts.on('--files PATH', 'JSON array of changed file paths') { |value| options[:files] = value }
    opts.on('--for NAME', 'Print only whether NAME is skipped') { |value| options[:for] = value }
  end

  argv = parser.parse(ARGV)
  command = argv.shift

  begin
    case command
    when 'resolve' then command_resolve(options)
    when 'relevant' then command_relevant(options)
    when 'verify-manifest' then command_verify_manifest(options)
    else
      warn parser.banner
      exit 1
    end
  rescue CiSkip::ManifestError, Errno::ENOENT, JSON::ParserError => error
    warn error.message
    exit 1
  end
end
