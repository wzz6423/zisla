#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifies the six Sparkle appcasts a release must serve: three architectures on the
# Gitee primary feed and three on the GitHub fallback. Parses the feeds as text so CI
# needs no XML toolchain, and takes an injectable fetcher so the tests stay offline.

require 'optparse'
require 'net/http'
require 'uri'

module AppcastFeeds
  class VerificationError < StandardError; end

  REPOSITORY = 'wzz6423/zisla'
  # A universal install keeps requesting the bare name, so it stays mapped to the
  # universal ZIP; the per-architecture names pin their own slice.
  ARCHIVES = {
    'appcast.xml' => 'universal',
    'appcast-arm64.xml' => 'arm64',
    'appcast-x86_64.xml' => 'x86_64'
  }.freeze
  FEED_ROOTS = {
    'release' => {
      'gitee' => "https://gitee.com/#{REPOSITORY}/releases/download/update-release",
      'github' => "https://github.com/#{REPOSITORY}/releases/latest/download"
    },
    'preview' => {
      'gitee' => "https://gitee.com/#{REPOSITORY}/releases/download/preview",
      'github' => "https://github.com/#{REPOSITORY}/releases/download/preview"
    }
  }.freeze

  # Downloads a feed and reports either its body or why it could not be read.
  class HTTPFetcher
    def initialize(redirect_limit: 5, timeout: 20)
      @redirect_limit = redirect_limit
      @timeout = timeout
    end

    def call(url)
      remaining = @redirect_limit
      current = url
      while remaining.positive?
        response = get(current)
        return [response.code.to_i, response.body.to_s] unless response.is_a?(Net::HTTPRedirection)

        current = response['location']
        remaining -= 1
      end
      [0, "exceeded #{@redirect_limit} redirects starting at #{url}"]
    rescue StandardError => error
      # A mirror that refuses the connection has to read as a verification failure with a
      # reason, not as a Ruby backtrace the release operator then has to decode.
      [0, "#{error.class}: #{error.message}"]
    end

    private

    # Every request carries its own deadline so one hung mirror cannot stall the run.
    def get(url)
      uri = URI.parse(url)
      Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == 'https', open_timeout: @timeout, read_timeout: @timeout
      ) { |http| http.request(Net::HTTP::Get.new(uri)) }
    end
  end

  class Verifier
    def initialize(tag:, channel:, fetcher:, hosts: FEED_ROOTS.fetch('release').keys)
      @tag = tag
      @channel = channel
      @fetcher = fetcher
      @hosts = hosts
    end

    def run
      roots = FEED_ROOTS[@channel]
      raise VerificationError, "unknown channel #{@channel}" if roots.nil?

      unknown = @hosts - roots.keys
      raise VerificationError, "unknown hosts #{unknown.join(', ')}" unless unknown.empty?
      raise VerificationError, 'at least one host is required' if @hosts.empty?

      @hosts.flat_map do |host|
        ARCHIVES.keys.flat_map { |name| verify_feed(host, roots.fetch(host), name) }
      end
    end

    private

    def verify_feed(host, root, name)
      url = "#{root}/#{name}"
      status, body = @fetcher.call(url)
      return ["#{url} could not be read: #{body}"] if status.zero?
      return ["#{url} returned HTTP #{status}"] if status != 200

      errors = []
      items = body.scan('<item>').length
      # One item per feed keeps an install from ever being offered another architecture.
      errors << "#{url} carries #{items} <item> elements instead of 1" if items != 1
      errors << "#{url} carries no sparkle:edSignature" unless body.match?(/sparkle:edSignature="[^"]+"/)
      errors << "#{url} carries no sparkle:version" unless body.match?(%r{<sparkle:version>[^<]+</sparkle:version>})
      errors.concat(verify_enclosure(url, host, name, body))
      errors
    end

    # Each feed must hand out its own site's copy of its own architecture, or a fallback
    # sends the client to an asset the other site may not carry.
    def verify_enclosure(url, host, name, body)
      architecture = ARCHIVES.fetch(name)
      expected = "https://#{host}.com/#{REPOSITORY}/releases/download/#{@tag}/" \
                 "zisla-#{@tag}-macOS-#{architecture}.zip"
      found = body[/<enclosure[^>]*\surl="([^"]+)"/, 1]
      return ["#{url} carries no enclosure url"] if found.nil?
      return [] if found == expected

      ["#{url} points at #{found} instead of #{expected}"]
    end
  end

  # The names a release has to carry. A missing appcast is invisible on the Release page yet
  # 404s every install of that architecture, so the asset list is checked as a set.
  def self.required_assets(tag:, layout:)
    return ARCHIVES.keys if layout == 'feed'
    raise VerificationError, "unknown layout #{layout}" unless layout == 'version'

    ARCHIVES.keys + ARCHIVES.values.flat_map do |architecture|
      base = "zisla-#{tag}-macOS-#{architecture}"
      %w[dmg dmg.sha256 zip zip.sha256].map { |extension| "#{base}.#{extension}" }
    end
  end

  # Screenshots and the source archives GitHub attaches on its own are extra, never missing.
  def self.missing_assets(tag:, layout:, names:)
    required_assets(tag: tag, layout: layout) - names.map(&:strip).reject(&:empty?)
  end

  def self.main(argv)
    options = { channel: 'release', hosts: FEED_ROOTS.fetch('release').keys, layout: 'version' }
    parser = OptionParser.new do |opts|
      opts.banner = <<~USAGE
        usage: appcast-feeds.rb verify --tag vX.Y.Z [--channel release|preview] [--hosts gitee,github]
               appcast-feeds.rb verify-assets --tag vX.Y.Z [--layout version|feed] < asset-names
      USAGE
      opts.on('--tag TAG', 'release tag the feeds must point at') { |value| options[:tag] = value }
      opts.on('--channel CHANNEL', 'release or preview') { |value| options[:channel] = value }
      opts.on('--hosts LIST', 'comma separated subset of gitee,github') do |value|
        options[:hosts] = value.split(',').map(&:strip).reject(&:empty?)
      end
      opts.on('--layout LAYOUT', 'version for a release, feed for a permanent feed release') do |value|
        options[:layout] = value
      end
    end
    parser.parse!(argv)
    command = argv.shift
    raise VerificationError, parser.banner unless %w[verify verify-assets].include?(command)
    raise VerificationError, 'a --tag is required' if options[:tag].to_s.empty?

    command == 'verify' ? verify_feeds(options) : verify_assets(options)
  end

  def self.verify_feeds(options)
    errors = Verifier.new(
      tag: options[:tag], channel: options[:channel],
      fetcher: HTTPFetcher.new, hosts: options[:hosts]
    ).run
    return report(errors) unless errors.empty?

    puts "every #{options[:channel]} appcast on #{options[:hosts].join(', ')} points at #{options[:tag]}"
    0
  end

  def self.verify_assets(options)
    missing = missing_assets(tag: options[:tag], layout: options[:layout], names: $stdin.read.lines)
    return report(missing.map { |name| "the #{options[:tag]} release carries no #{name}" }) unless missing.empty?

    puts "the #{options[:tag]} release carries every required #{options[:layout]} asset"
    0
  end

  def self.report(errors)
    errors.each { |error| warn "error: #{error}" }
    1
  end
end

exit AppcastFeeds.main(ARGV) if $PROGRAM_NAME == __FILE__
