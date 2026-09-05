#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifies the Homebrew cask that serves `brew install --cask wzz6423/tap/zisla`.
# Parses the cask as text instead of loading it, so CI needs no Homebrew install.

require 'optparse'

module HomebrewCask
  class VerificationError < StandardError; end

  RELEASE_VERSION = /\A\d+\.\d+\.\d+\z/
  SHA256 = /\A[0-9a-f]{64}\z/
  # Both placeholders stay unresolved on purpose: version keeps a release bump from
  # leaving the URL behind, and arch keeps every machine on its own slice.
  ARCHIVE_URL = 'https://github.com/wzz6423/zisla/releases/download/v#{version}/' \
                'zisla-v#{version}-macOS-#{arch}.zip'
  ZAP_PATHS = [
    '~/Library/Application Support/zisla',
    '~/Library/Caches/dev.wzz.zisla',
    '~/Library/HTTPStorages/dev.wzz.zisla',
    '~/Library/Preferences/dev.wzz.zisla.plist',
    '~/Library/Saved Application State/dev.wzz.zisla.savedState'
  ].freeze
  REQUIRED_LINES = {
    'cask header' => 'cask "zisla" do',
    # Homebrew resolves the arch token per machine, so one cask serves both chips.
    'architecture map' => '  arch arm: "arm64", intel: "x86_64"',
    'name' => '  name "zisla"',
    'homepage' => '  homepage "https://github.com/wzz6423/zisla"',
    'app artifact' => '  app "zisla.app"',
    # Sparkle ships the updates, so brew defers unless the installed app is really stale.
    'auto_updates' => '  auto_updates true',
    'minimum macOS' => '  depends_on macos: :sonoma',
    'livecheck block' => '  livecheck do'
  }.freeze

  class Verifier
    def initialize(source, expected_version: nil, content_source: nil)
      @source = source
      @expected_version = expected_version
      @content_source = content_source
    end

    def run
      errors = []
      REQUIRED_LINES.each do |label, line|
        errors << "cask is missing its #{label} line: #{line.strip}" unless @source.include?("#{line}\n")
      end
      errors.concat(verify_version)
      errors.concat(verify_checksum)
      errors.concat(verify_url)
      errors.concat(verify_zap)
      errors.concat(verify_description)
      errors.concat(verify_content_alignment)
      errors
    end

    private

    def version
      @version ||= @source[/^  version "([^"]*)"$/, 1]
    end

    def verify_version
      return ['cask declares no version'] if version.nil?

      errors = []
      unless RELEASE_VERSION.match?(version)
        errors << "cask version #{version.inspect} is not a release version such as 1.2.3"
      end
      if @expected_version && version != @expected_version
        errors << "cask version #{version.inspect} does not match the requested #{@expected_version.inspect}"
      end
      errors
    end

    def verify_checksum
      digests = @source.match(/^  sha256 arm:\s+"([^"]*)",\s+intel:\s+"([^"]*)"$/)
      return ['cask declares no per-architecture sha256'] if digests.nil?

      errors = digests.captures.reject { |digest| SHA256.match?(digest) }.map do |digest|
        "cask sha256 #{digest.inspect} is not a lowercase SHA-256 digest"
      end
      # One digest in both slots means an architecture would fetch the other's archive.
      errors << 'cask reuses one sha256 for both architectures' if digests[1] == digests[2]
      errors
    end

    def verify_url
      declared = @source[/^  url "([^"]*)",$/, 1]
      return ['cask declares no url, or its url carries no verified owner'] if declared.nil?
      return [] if declared == ARCHIVE_URL

      ["cask url #{declared.inspect} does not match #{ARCHIVE_URL.inspect}"]
    end

    def verify_zap
      missing = ZAP_PATHS.reject { |path| @source.include?("    \"#{path}\",\n") }
      return [] if missing.empty?

      ["cask zap does not trash #{missing.join(', ')}"]
    end

    def verify_description
      description = @source[/^  desc "([^"]*)"$/, 1]
      return ['cask declares no desc'] if description.nil?

      errors = []
      errors << 'cask desc must not start with the cask name' if description.start_with?('zisla')
      errors << 'cask desc must not end with a period' if description.end_with?('.')
      errors
    end

    # The site hardcodes the release it links to, so a cask bump without a site bump
    # would leave Homebrew and the download section on different versions.
    def verify_content_alignment
      return [] if @content_source.nil? || version.nil?

      site_version = @content_source[/^  version: '([^']*)',$/, 1]
      return ['web/src/content.ts declares no latestRelease version'] if site_version.nil?
      return [] if site_version == "v#{version}"

      ["cask version v#{version} does not match the site's latestRelease #{site_version}"]
    end
  end
end

def command_verify(options)
  content_source = options[:content] && File.read(options[:content])
  errors = HomebrewCask::Verifier.new(
    File.read(options[:cask]),
    expected_version: options[:version],
    content_source: content_source
  ).run
  errors.each { |error| warn error }
  unless errors.empty?
    raise HomebrewCask::VerificationError, "cask verification failed with #{errors.length} error(s)"
  end

  puts "Verified #{options[:cask]}."
end

if $PROGRAM_NAME == __FILE__
  options = { cask: File.expand_path('../../Casks/zisla.rb', __dir__) }
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: homebrew-cask.rb verify [options]'
    opts.on('--cask PATH', 'Cask path') { |value| options[:cask] = value }
    opts.on('--version VERSION', 'Version the cask must pin') { |value| options[:version] = value }
    opts.on('--content PATH', 'web/src/content.ts, to compare against latestRelease') do |value|
      options[:content] = value
    end
  end

  argv = parser.parse(ARGV)
  command = argv.shift

  begin
    case command
    when 'verify' then command_verify(options)
    else
      warn parser.banner
      exit 1
    end
  rescue HomebrewCask::VerificationError, Errno::ENOENT => error
    warn error.message
    exit 1
  end
end
