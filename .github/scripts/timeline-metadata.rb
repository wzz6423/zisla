#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative 'project-metadata'

module TimelineMetadata
  START_MARKER = '<!-- zisla-timeline:start -->'
  END_MARKER = '<!-- zisla-timeline:end -->'
  BLOCK = /\n*^#{Regexp.escape(START_MARKER)}\n.*?^#{Regexp.escape(END_MARKER)}(?:\n|\z)/m

  def self.render(event, current_body)
    timestamps = ProjectMetadata.timestamps_for(event)
    lines = [START_MARKER, '## Timeline', "- Submitted: #{format_time(timestamps.fetch('createdAt'))}"]
    lines << "- Ended: #{format_time(timestamps['endedAt'])}" if timestamps['endedAt']
    lines << END_MARKER

    body = current_body.to_s.gsub("\r\n", "\n")
    base = body.sub(BLOCK, '').sub(/\n+\z/, '')
    updated = [base, lines.join("\n")].reject(&:empty?).join("\n\n")
    { 'changed' => updated != body, 'body' => updated }
  end

  def self.format_time(timestamp)
    ProjectMetadata.local_time(timestamp).strftime('%F %T UTC%:z')
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: timeline-metadata.rb --event-file PATH --resource-file PATH'
    opts.on('--event-file PATH', 'GitHub event payload') { |value| options[:event_file] = value }
    opts.on('--resource-file PATH', 'Current Issue or pull request API response') { |value| options[:resource_file] = value }
  end
  parser.parse!(ARGV)

  begin
    event = JSON.parse(File.read(options.fetch(:event_file)))
    resource = JSON.parse(File.read(options.fetch(:resource_file)))
    resource_type = event.key?('issue') ? 'issue' : 'pull_request'
    puts JSON.generate(TimelineMetadata.render({ resource_type => resource }, resource['body']))
  rescue ProjectMetadata::ContractError, KeyError, Errno::ENOENT, JSON::ParserError, TypeError => error
    warn error.message
    exit 1
  end
end
