#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'time'
require_relative 'pr-metadata'

module ProjectMetadata
  TIME_ZONE_OFFSET = '+08:00'
  class ContractError < StandardError; end

  class Contract
    def self.load(path)
      new(JSON.parse(File.read(path)))
    rescue JSON::ParserError => error
      raise ContractError, "#{path}: invalid JSON (#{error.message})"
    end

    def initialize(document)
      @default_status = document.fetch('defaultStatus')
      @closed_status = document.fetch('closedStatus')
      @label_status = Array(document.fetch('labelStatus'))
    end

    def status_for(state:, labels:, type_label: nil)
      return @closed_status if state == 'closed'

      names = Array(labels).map(&:to_s)
      names << type_label.to_s unless type_label.to_s.empty?
      rule = @label_status.find { |candidate| names.include?(candidate.fetch('label')) }
      rule ? rule.fetch('status') : @default_status
    end
  end

  def self.labels_from(json)
    labels = JSON.parse(json)
    raise ContractError, 'labels must be a JSON array' unless labels.is_a?(Array)

    labels
  rescue JSON::ParserError => error
    raise ContractError, "labels: invalid JSON (#{error.message})"
  end

  def self.timestamps_for(event)
    content = event['issue'] || event['pull_request']
    raise ContractError, 'event must contain an Issue or pull request' unless content.is_a?(Hash)

    created_at = content.fetch('created_at')
    state = content.fetch('state')

    ended_at = state == 'closed' ? content['merged_at'] || content['closed_at'] : nil
    raise ContractError, 'closed item has no end time' if state == 'closed' && ended_at.to_s.empty?

    { 'createdAt' => created_at, 'endedAt' => ended_at }
  end

  def self.local_time(timestamp)
    Time.iso8601(timestamp).getlocal(TIME_ZONE_OFFSET)
  rescue ArgumentError
    raise ContractError, "invalid event timestamp #{timestamp.inspect}"
  end

  def self.dates_for(event)
    timestamps = timestamps_for(event)
    dates = {
      'submittedDate' => local_time(timestamps.fetch('createdAt')).strftime('%F'),
      'endDate' => timestamps['endedAt'] && local_time(timestamps['endedAt']).strftime('%F')
    }
    if event['pull_request']
      sections = PullRequestMetadata.sections(event['pull_request']['body'])
      dates.merge!(PullRequestMetadata.project_dates(sections['GitHub Project']).compact)
    end
    dates
  rescue PullRequestMetadata::ContractError => error
    raise ContractError, error.message
  end
end

def command_status(options, contract)
  puts contract.status_for(
    state: options.fetch(:state),
    labels: ProjectMetadata.labels_from(options.fetch(:labels)),
    type_label: options[:type_label]
  )
end

def command_dates(options)
  puts JSON.generate(ProjectMetadata.dates_for(JSON.parse(File.read(options.fetch(:event_file)))))
end

if $PROGRAM_NAME == __FILE__
  options = { manifest: File.expand_path('../project-automation.json', __dir__) }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: project-metadata.rb <status|dates> [options]'
    opts.on('--manifest PATH', 'Project automation contract path') { |value| options[:manifest] = value }
    opts.on('--state STATE', 'Issue or pull request state') { |value| options[:state] = value }
    opts.on('--labels-json JSON', 'Event label names as a JSON array') { |value| options[:labels] = value }
    opts.on('--type-label LABEL', 'Type label parsed from a pull request body') { |value| options[:type_label] = value }
    opts.on('--event-file PATH', 'GitHub Issue or pull request event payload') { |value| options[:event_file] = value }
  end

  command = parser.parse(ARGV).shift

  begin
    contract = ProjectMetadata::Contract.load(options[:manifest])
    case command
    when 'status' then command_status(options, contract)
    when 'dates' then command_dates(options)
    else
      warn parser.banner
      exit 1
    end
  rescue ProjectMetadata::ContractError, KeyError, Errno::ENOENT, JSON::ParserError, TypeError => error
    warn error.message
    exit 1
  end
end
