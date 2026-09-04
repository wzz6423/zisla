#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'yaml'

# Parses and validates the issue form contract.
#
# GitHub renders an Issue Form as one `### <field label>` section per field, and
# that label is localized, so the field ids in .github/ISSUE_TEMPLATE are the
# only identity shared by the English and the Simplified Chinese form. This
# module reads the shipped forms to build the heading map for every locale, then
# reports the labels the Issue Automation workflow applies and every reason the
# issue is still incomplete. An incomplete issue is data, never an exception, so
# the workflow can label it instead of failing.
module IssueMetadata
  NO_RESPONSE = /\A_+no response_+\z/i
  FENCE = /\A[[:space:]]{0,3}(`{3,}|~{3,})/
  HEADING = /\A###[[:space:]]+(.+?)[[:space:]]*\z/
  CHECKBOX = /\A[[:space:]]*[-*][[:space:]]+\[([ xX])\][[:space:]]*(.*?)[[:space:]]*\z/
  REPORTED_VALUE_LIMIT = 80

  class ContractError < StandardError; end

  def self.normalize(value)
    value.to_s.gsub(/[[:space:]]+/, ' ').strip.downcase
  end

  # Keeps an echoed value short: the reported text lands in a bot comment.
  def self.truncate(value)
    text = value.to_s.gsub(/[[:space:]]+/, ' ').strip
    text.length > REPORTED_VALUE_LIMIT ? "#{text[0, REPORTED_VALUE_LIMIT]}…" : text
  end

  # One shipped Issue Form, keyed by field id so a localized heading resolves
  # back to the field the contract talks about.
  class Form
    attr_reader :file, :kind, :title, :labels, :fields

    def initialize(file:, kind:, document:)
      @file = file
      @kind = kind
      @title = document['title'].to_s
      @labels = Array(document['labels']).map(&:to_s)
      @fields = read_fields(document)
    end

    def label_for(id)
      @fields.dig(id, 'label')
    end

    def options_for(id)
      Array(@fields.dig(id, 'options'))
    end

    def required_ids
      @fields.select { |_, field| field['required'] }.keys
    end

    def required_options
      @fields.values.flat_map { |field| field['requiredOptions'] }
    end

    def score(headings)
      (@fields.values.map { |field| field['label'] } & Array(headings)).length
    end

    private

    def read_fields(document)
      Array(document['body']).each_with_object({}) do |element, map|
        id = element['id'].to_s
        type = element['type'].to_s
        # A markdown block renders no heading, so it carries no field identity.
        next if id.empty? || type == 'markdown'

        attributes = element['attributes'] || {}
        map[id] = {
          'type' => type,
          'label' => attributes['label'].to_s,
          'required' => (element['validations'] || {})['required'] == true,
          'options' => type == 'dropdown' ? Array(attributes['options']).map(&:to_s) : [],
          'requiredOptions' => required_option_labels(type, attributes)
        }
      end
    end

    def required_option_labels(type, attributes)
      return [] unless type == 'checkboxes'

      Array(attributes['options']).select { |option| option['required'] == true }
                                  .map { |option| option['label'].to_s }
    end
  end

  # Every shipped Issue Form, in contract order so a scoring tie resolves to the
  # English form.
  class Forms
    def initialize(forms)
      @forms = forms
    end

    def all
      @forms
    end

    def for_kind(kind)
      @forms.select { |form| form.kind == kind }
    end

    # Picks the form whose localized labels the body actually used, which is the
    # only way to tell an English body from a Simplified Chinese one.
    def detect(headings)
      best = nil
      best_score = 0
      @forms.each do |form|
        score = form.score(headings)
        next unless score > best_score

        best = form
        best_score = score
      end
      best
    end
  end

  # The label contract shared with .github/ISSUE_TEMPLATE.
  class Contract
    attr_reader :kinds, :areas, :area_field, :template_dir

    def self.load(path)
      new(JSON.parse(File.read(path)), File.join(File.dirname(path), 'ISSUE_TEMPLATE'))
    rescue JSON::ParserError => error
      raise ContractError, "#{path}: invalid JSON (#{error.message})"
    end

    def initialize(document, template_dir)
      @kinds = Array(document['kinds'])
      @areas = Array(document['areas'])
      raise ContractError, 'contract declares no kinds' if @kinds.empty?
      raise ContractError, 'contract declares no areas' if @areas.empty?

      @area_field = document.fetch('areaField')
      @needs_more_info = document.fetch('needsMoreInfoLabel')
      @template_dir = template_dir
    end

    def forms
      @forms ||= Forms.new(@kinds.flat_map do |kind|
        Array(kind['templates']).map { |file| load_form(kind, file) }
      end)
    end

    def kind_for_title(title)
      normalized = title.to_s.strip
      @kinds.find { |kind| normalized.start_with?(kind['titlePrefix'].to_s) }
    end

    def title_summary(title)
      kind = kind_for_title(title)
      return nil if kind.nil?

      title.to_s.strip.delete_prefix(kind['titlePrefix'].to_s).strip
    end

    def title_prefixes
      @kinds.map { |kind| kind['titlePrefix'] }
    end

    def area_for(value)
      normalized = IssueMetadata.normalize(value)
      return nil if normalized.empty?

      @areas.find do |area|
        ([area['area']] + Array(area['aliases'])).any? do |name|
          IssueMetadata.normalize(name) == normalized
        end
      end
    end

    def area_names
      @areas.map { |area| area['area'] }
    end

    def needs_more_info_label
      @needs_more_info['label']
    end

    def declared_labels
      @kinds.map { |kind| kind['label'] } +
        @areas.map { |area| area.slice('label', 'color', 'description') } +
        [@needs_more_info]
    end

    def managed_labels
      declared_labels.uniq { |entry| entry['label'] }
    end

    def managed_label_names
      managed_labels.map { |entry| entry['label'] }
    end

    private

    def load_form(kind, file)
      path = File.join(@template_dir, file)
      Form.new(file: file, kind: kind['kind'], document: YAML.safe_load(File.read(path)))
    rescue Errno::ENOENT
      raise ContractError, "#{file}: issue form not found in #{@template_dir}"
    rescue Psych::SyntaxError => error
      raise ContractError, "#{file}: invalid YAML (#{error.message})"
    end
  end

  def self.sections(body)
    fence = nil
    current = nil
    body.to_s.gsub("\r\n", "\n").each_line.each_with_object({}) do |raw_line, map|
      line = raw_line.chomp
      marker = line[FENCE, 1]

      # A `render:` textarea is emitted inside a fence, so a log line that looks
      # like a heading must never open a section.
      if fence
        fence = nil if marker && marker[0] == fence[0] && marker.length >= fence.length
        map[current] << line if current && marker.nil?
        next
      end

      if marker
        fence = marker
        next
      end

      heading = line.match(HEADING)
      if heading
        current = heading[1]
        map[current] ||= []
      elsif current
        map[current] << line
      end
    end
  end

  def self.value_of(lines)
    value = Array(lines).join("\n").strip
    return nil if value.empty? || NO_RESPONSE.match?(value)

    value
  end

  def self.read_values(form, sections)
    form.fields.each_with_object({}) do |(id, field), values|
      value = value_of(sections[field['label']])
      values[id] = value unless value.nil?
    end
  end

  # Only the checkbox sections are read, so a `- [x]` line typed into a textarea
  # cannot satisfy a required acknowledgement.
  def self.checked_options(form, sections)
    form.fields.values.select { |field| field['type'] == 'checkboxes' }
        .flat_map { |field| Array(sections[field['label']]) }
        .filter_map do |line|
          match = CHECKBOX.match(line)
          next if match.nil? || match[1].strip.empty?

          match[2]
        end
  end

  def self.analyze(title:, body:, contract:)
    kind = contract.kind_for_title(title)
    parsed = sections(body)
    detected = contract.forms.detect(parsed.keys)
    form = detected || (kind && contract.forms.for_kind(kind['kind']).first)
    values = form ? read_values(form, parsed) : {}
    area = contract.area_for(values[contract.area_field])

    metadata = {
      'kind' => kind && kind['kind'],
      'kindLabel' => kind && kind['label']['label'],
      'titlePrefix' => kind && kind['titlePrefix'],
      'titleSummary' => contract.title_summary(title),
      'form' => form && form.file,
      'formDetected' => !detected.nil?,
      'area' => area && area['area'],
      'areaRaw' => values[contract.area_field],
      'areaLabel' => area && area['label'],
      'values' => values,
      'checked' => form ? checked_options(form, parsed) : []
    }

    errors = validate(metadata, form, contract)
    metadata.merge(
      'errors' => errors,
      'valid' => errors.empty?,
      'labels' => labels(metadata, errors, contract),
      'managedLabels' => contract.managed_label_names
    )
  end

  def self.labels(metadata, errors, contract)
    labels = [metadata['kindLabel'], metadata['areaLabel']].compact
    labels << contract.needs_more_info_label unless errors.empty?
    labels.uniq
  end

  def self.validate(metadata, form, contract)
    validate_title(metadata, contract) +
      validate_form(metadata, form) +
      validate_values(metadata, form) +
      validate_checkboxes(metadata, form) +
      validate_area(metadata, form, contract)
  end

  def self.validate_title(metadata, contract)
    if metadata['kind'].nil?
      return ["Title must start with #{contract.title_prefixes.join(' or ')} followed by a short summary, " \
              'for example "[Bug] Voice input is not written to the current text field".']
    end
    return [] unless metadata['titleSummary'].to_s.empty?

    ["Title must add a short summary after #{metadata['titlePrefix']}."]
  end

  def self.validate_form(metadata, form)
    if form.nil?
      return ['The body matches no Issue Form. Open the issue with the Bug report or the Feature request form.']
    end
    unless metadata['formDetected']
      return ["The body matches no Issue Form. Fill in every \"### <field>\" section that #{form.file} renders."]
    end
    return [] if metadata['kind'].nil? || metadata['kind'] == form.kind

    ["The body was filled in with #{form.file}, which does not match the #{metadata['titlePrefix']} title."]
  end

  def self.validate_values(metadata, form)
    return [] if form.nil?

    form.required_ids.filter_map do |id|
      next if metadata['values'][id]

      "Section \"### #{form.label_for(id)}\" is required and must not be empty."
    end
  end

  def self.validate_checkboxes(metadata, form)
    return [] if form.nil?

    checked = Array(metadata['checked']).map { |option| IssueMetadata.normalize(option) }
    form.required_options.filter_map do |option|
      next if checked.include?(IssueMetadata.normalize(option))

      "Required checkbox #{option.inspect} must be checked."
    end
  end

  def self.validate_area(metadata, form, contract)
    # A missing value is already reported as a missing required section.
    return [] if metadata['area'] || metadata['areaRaw'].nil?

    label = (form && form.label_for(contract.area_field)) || contract.area_field
    allowed = form ? form.options_for(contract.area_field) : []
    allowed = contract.area_names if allowed.empty?
    ["Section \"### #{label}\" value #{truncate(metadata['areaRaw']).inspect} is not allowed. " \
     "Select one of: #{allowed.join(', ')}."]
  end

  # Checks that the contract and the shipped forms still agree, so a renamed
  # field or a reordered dropdown fails CI instead of silently dropping labels.
  def self.verify(contract)
    verify_labels(contract) + verify_forms(contract) + verify_headings(contract)
  end

  def self.verify_labels(contract)
    seen = {}
    contract.declared_labels.flat_map do |entry|
      name = entry['label'].to_s
      problems = []
      problems << 'a managed label declares no name' if name.empty?
      problems << "label #{name.inspect} is declared twice" if seen.key?(name)
      seen[name] = true
      unless /\A[0-9a-f]{6}\z/.match?(entry['color'].to_s)
        problems << "label #{name.inspect} needs a six digit lowercase hex color"
      end
      problems << "label #{name.inspect} needs a description" if entry['description'].to_s.strip.empty?
      problems
    end
  end

  def self.verify_forms(contract)
    contract.kinds.flat_map do |kind|
      forms = contract.forms.for_kind(kind['kind'])
      next ["kind #{kind['kind'].inspect} declares no issue form"] if forms.empty?

      forms.flat_map { |form| verify_form(form, kind, contract) } +
        forms.drop(1).flat_map { |form| verify_localization(forms.first, form) }
    end
  end

  def self.verify_form(form, kind, contract)
    problems = []
    unless form.title.start_with?(kind['titlePrefix'].to_s)
      problems << "#{form.file}: title #{form.title.inspect} must start with #{kind['titlePrefix']}"
    end
    unless form.labels.include?(kind['label']['label'])
      problems << "#{form.file}: labels must include #{kind['label']['label'].inspect}"
    end

    field = form.fields[contract.area_field]
    return problems + ["#{form.file}: declares no field with id #{contract.area_field.inspect}"] if field.nil?

    unless field['type'] == 'dropdown' && field['required']
      problems << "#{form.file}: field #{contract.area_field.inspect} must be a required dropdown"
    end
    problems + verify_area_options(form, field, contract)
  end

  def self.verify_area_options(form, field, contract)
    options = Array(field['options'])
    if options.length != contract.areas.length
      return ["#{form.file}: #{contract.area_field} declares #{options.length} option(s), " \
              "the contract declares #{contract.areas.length}"]
    end

    options.each_with_index.filter_map do |option, index|
      area = contract.areas[index]
      accepted = [area['area']] + Array(area['aliases'])
      next if accepted.any? { |name| normalize(name) == normalize(option) }

      "#{form.file}: option #{option.inspect} does not map to #{area['area'].inspect}"
    end
  end

  def self.verify_localization(reference, form)
    problems = []
    if reference.fields.keys != form.fields.keys
      problems << "#{form.file}: field ids #{form.fields.keys.inspect} differ from " \
                  "#{reference.file} #{reference.fields.keys.inspect}"
    end
    if reference.required_ids != form.required_ids
      problems << "#{form.file}: required field ids differ from #{reference.file}"
    end
    if reference.required_options.length != form.required_options.length
      problems << "#{form.file}: required checkbox count differs from #{reference.file}"
    end
    problems
  end

  def self.verify_headings(contract)
    owners = {}
    contract.forms.all.flat_map do |form|
      form.fields.filter_map do |id, field|
        label = field['label']
        next "#{form.file}: field #{id.inspect} declares no label" if label.empty?

        owner = owners[label]
        owners[label] = id
        next if owner.nil? || owner == id

        "#{form.file}: heading #{label.inspect} maps to both #{owner.inspect} and #{id.inspect}"
      end
    end
  end
end

def analyze_files(options, contract)
  IssueMetadata.analyze(
    title: File.read(options[:title_file]),
    body: File.read(options[:body_file]),
    contract: contract
  )
end

# Reports the labels only. Field values stay out of the output so no issue text
# is echoed into the workflow log.
def command_json(options, contract)
  report = analyze_files(options, contract)
  puts JSON.pretty_generate(
    report.slice('kind', 'kindLabel', 'form', 'formDetected', 'area', 'areaLabel')
          .merge(report.slice('labels', 'managedLabels', 'errors', 'valid'))
  )
end

def command_validate(options, contract)
  report = analyze_files(options, contract)
  if report['valid']
    puts 'Issue metadata is valid.'
    return
  end

  report['errors'].each { |error| warn error }
  warn 'See CONTRIBUTING.md and .github/ISSUE_TEMPLATE for the required title and fields.'
  exit 1
end

def command_verify_manifest(contract)
  problems = IssueMetadata.verify(contract)
  if problems.empty?
    puts "Issue automation contract matches #{contract.forms.all.length} issue form(s)."
    return
  end

  problems.each { |problem| warn problem }
  exit 1
end

if $PROGRAM_NAME == __FILE__
  options = { manifest: File.expand_path('../issue-automation.json', __dir__) }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: issue-metadata.rb <json|validate|labels|verify-manifest> [options]'
    opts.on('--manifest PATH', 'Label contract path') { |value| options[:manifest] = value }
    opts.on('--title-file PATH', 'File holding the issue title') { |value| options[:title_file] = value }
    opts.on('--body-file PATH', 'File holding the issue body') { |value| options[:body_file] = value }
  end

  argv = parser.parse(ARGV)
  command = argv.shift

  begin
    contract = IssueMetadata::Contract.load(options[:manifest])
    case command
    when 'json' then command_json(options, contract)
    when 'validate' then command_validate(options, contract)
    when 'labels' then puts JSON.pretty_generate(contract.managed_labels)
    when 'verify-manifest' then command_verify_manifest(contract)
    else
      warn parser.banner
      exit 1
    end
  rescue IssueMetadata::ContractError, KeyError, Errno::ENOENT, JSON::ParserError, TypeError => error
    warn error.message
    exit 1
  end
end
