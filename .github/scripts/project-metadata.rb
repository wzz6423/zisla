#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'

module ProjectMetadata
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
end

def command_status(options, contract)
  puts contract.status_for(
    state: options.fetch(:state),
    labels: ProjectMetadata.labels_from(options.fetch(:labels)),
    type_label: options[:type_label]
  )
end

if $PROGRAM_NAME == __FILE__
  options = { manifest: File.expand_path('../project-automation.json', __dir__) }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: project-metadata.rb status --state STATE --labels-json JSON [options]'
    opts.on('--manifest PATH', 'Project automation contract path') { |value| options[:manifest] = value }
    opts.on('--state STATE', 'Issue or pull request state') { |value| options[:state] = value }
    opts.on('--labels-json JSON', 'Event label names as a JSON array') { |value| options[:labels] = value }
    opts.on('--type-label LABEL', 'Type label parsed from a pull request body') { |value| options[:type_label] = value }
  end

  command = parser.parse(ARGV).shift

  begin
    contract = ProjectMetadata::Contract.load(options[:manifest])
    case command
    when 'status' then command_status(options, contract)
    else
      warn parser.banner
      exit 1
    end
  rescue ProjectMetadata::ContractError, KeyError, Errno::ENOENT, TypeError => error
    warn error.message
    exit 1
  end
end
