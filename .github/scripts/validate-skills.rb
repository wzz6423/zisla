#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'uri'
require 'yaml'

ALLOWED_FIELDS = %w[name description license compatibility metadata allowed-tools].freeze
NAME_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
MARKDOWN_LINK_PATTERN = /!?\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|([^\s)]+))[^\n]*?\)/

class SkillValidator
  def initialize(skills_directory)
    @skills_directory = skills_directory.expand_path
    @errors = []
  end

  def run
    fail_with('skills directory not found') unless @skills_directory.directory?

    skill_directories = @skills_directory.children.select(&:directory?).sort
    fail_with('no skill directories found') if skill_directories.empty?

    skill_directories.each { |directory| validate_skill(directory) }

    if @errors.empty?
      puts "Validated #{skill_directories.length} skill(s)."
      return true
    end

    @errors.each { |path, message| warn "#{path}: #{message}" }
    warn "Skill validation failed with #{@errors.length} error(s)."
    false
  end

  private

  def fail_with(message)
    warn message
    exit 1
  end

  def add_error(path, message)
    @errors << [path.relative_path_from(@skills_directory.parent), message]
  end

  def validate_skill(directory)
    skill_file = directory / 'SKILL.md'
    unless skill_file.file?
      add_error(skill_file, 'SKILL.md is missing')
      return
    end

    frontmatter, body = parse_skill(skill_file)
    return unless frontmatter

    validate_frontmatter(skill_file, directory.basename.to_s, frontmatter)
    add_error(skill_file, 'Markdown body must not be empty') if body.strip.empty?
    validate_links(skill_file, directory, body)
  end

  def parse_skill(skill_file)
    content = skill_file.read(encoding: 'UTF-8')
    match = content.match(/\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*\r?\n(.*)\z/m)
    unless match
      add_error(skill_file, 'YAML frontmatter is missing or malformed')
      return
    end

    frontmatter = YAML.safe_load(match[1], permitted_classes: [], permitted_symbols: [], aliases: false)
    unless frontmatter.is_a?(Hash)
      add_error(skill_file, 'frontmatter must be a YAML mapping')
      return
    end

    [frontmatter, match[2]]
  rescue EncodingError, Psych::Exception => e
    add_error(skill_file, "frontmatter could not be parsed: #{e.message.lines.first.strip}")
    nil
  end

  def validate_frontmatter(skill_file, directory_name, frontmatter)
    unknown_fields = frontmatter.keys.reject { |key| key.is_a?(String) && ALLOWED_FIELDS.include?(key) }
    add_error(skill_file, "unsupported frontmatter field(s): #{unknown_fields.join(', ')}") unless unknown_fields.empty?

    validate_name(skill_file, directory_name, frontmatter['name'])
    validate_string(skill_file, frontmatter, 'description', maximum: 1024, required: true)
    validate_string(skill_file, frontmatter, 'license')
    validate_string(skill_file, frontmatter, 'compatibility', maximum: 500)
    validate_string(skill_file, frontmatter, 'allowed-tools')
    validate_metadata(skill_file, frontmatter['metadata']) if frontmatter.key?('metadata')
  end

  def validate_name(skill_file, directory_name, name)
    unless name.is_a?(String) && !name.empty?
      add_error(skill_file, 'name must be a non-empty string')
      return
    end

    add_error(skill_file, 'name must use lowercase letters, digits, and single hyphens') unless name.match?(NAME_PATTERN)
    add_error(skill_file, 'name must contain at most 64 characters') if name.length > 64
    add_error(skill_file, "name must match its directory (#{directory_name})") unless name == directory_name
  end

  def validate_string(skill_file, frontmatter, field, maximum: nil, required: false)
    unless frontmatter.key?(field)
      add_error(skill_file, "#{field} is required") if required
      return
    end

    value = frontmatter[field]
    unless value.is_a?(String) && !value.strip.empty?
      add_error(skill_file, "#{field} must be a non-empty string")
      return
    end

    add_error(skill_file, "#{field} must contain at most #{maximum} characters") if maximum && value.length > maximum
  end

  def validate_metadata(skill_file, metadata)
    unless metadata.is_a?(Hash)
      add_error(skill_file, 'metadata must be a mapping')
      return
    end

    return if metadata.all? { |key, value| key.is_a?(String) && value.is_a?(String) }

    add_error(skill_file, 'metadata keys and values must be strings')
  end

  def validate_links(skill_file, skill_directory, body)
    body.scan(MARKDOWN_LINK_PATTERN) do |angle_destination, plain_destination|
      destination = (angle_destination || plain_destination).gsub(/\\([\\() ])/, '\\1')
      next if destination.start_with?('#', '//') || destination.match?(/\A[a-z][a-z0-9+.-]*:/i)

      local_path = URI::DEFAULT_PARSER.unescape(destination.split(/[?#]/, 2).first)
      next if local_path.empty?

      validate_local_path(skill_file, skill_directory, local_path)
    rescue ArgumentError => e
      add_error(skill_file, "invalid local Markdown reference #{destination.inspect}: #{e.message}")
    end
  end

  def validate_local_path(skill_file, skill_directory, local_path)
    root = skill_directory.realpath
    target = (root / local_path).cleanpath

    unless contained_by?(target, root)
      add_error(skill_file, "local Markdown reference escapes the skill directory: #{local_path}")
      return
    end

    unless target.exist?
      add_error(skill_file, "local Markdown reference does not exist: #{local_path}")
      return
    end

    return if contained_by?(target.realpath, root)

    add_error(skill_file, "local Markdown reference resolves outside the skill directory: #{local_path}")
  end

  def contained_by?(path, root)
    relative = path.relative_path_from(root)
    !relative.absolute? && relative.each_filename.first != '..'
  rescue ArgumentError
    false
  end
end

if $PROGRAM_NAME == __FILE__
  skills_directory = Pathname.new(__dir__).join('../..', 'skills')
  exit(SkillValidator.new(skills_directory).run ? 0 : 1)
end
