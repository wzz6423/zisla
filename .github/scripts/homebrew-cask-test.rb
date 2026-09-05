#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative 'homebrew-cask'

class HomebrewCaskTest < Minitest::Test
  CASK_PATH = File.expand_path('../../Casks/zisla.rb', __dir__)
  CONTENT_PATH = File.expand_path('../../web/src/content.ts', __dir__)

  def setup
    @cask = File.read(CASK_PATH)
    @content = File.read(CONTENT_PATH)
  end

  def errors(source, expected_version: nil, content_source: nil)
    HomebrewCask::Verifier.new(source, expected_version: expected_version, content_source: content_source).run
  end

  def cask_version
    @cask[/^  version "([^"]*)"$/, 1]
  end

  def test_shipped_cask_passes_every_check
    assert_empty errors(@cask, expected_version: cask_version, content_source: @content)
  end

  def test_shipped_cask_and_site_pin_the_same_release
    assert_equal "v#{cask_version}", @content[/^  version: '([^']*)',$/, 1]
  end

  def test_requested_version_must_match
    assert_includes errors(@cask, expected_version: '9.9.9').join("\n"), 'does not match the requested'
  end

  def test_prerelease_version_is_rejected
    source = @cask.sub(/^  version ".*"$/, '  version "0.2.0-preview.1"')
    assert_includes errors(source).join("\n"), 'is not a release version'
  end

  def test_uppercase_checksum_is_rejected
    source = @cask.sub(/^(  sha256 arm:\s+)"[^"]*"/) { "#{Regexp.last_match(1)}\"#{'A' * 64}\"" }
    assert_includes errors(source).join("\n"), 'is not a lowercase SHA-256 digest'
  end

  def test_missing_intel_checksum_is_rejected
    source = @cask.sub(/,\n\s+intel: "[^"]*"/, '')
    assert_includes errors(source).join("\n"), 'no per-architecture sha256'
  end

  # Both slots carrying one digest would send Intel machines to the arm64 archive.
  def test_reused_checksum_is_rejected
    arm = @cask[/^  sha256 arm:\s+"([^"]*)"/, 1]
    source = @cask.sub(/^(\s+intel: )"[^"]*"/) { "#{Regexp.last_match(1)}\"#{arm}\"" }
    assert_includes errors(source).join("\n"), 'reuses one sha256'
  end

  def test_missing_arch_stanza_is_rejected
    source = @cask.sub(/^  arch .*\n\n/, '')
    assert_includes errors(source).join("\n"), 'architecture map'
  end

  def test_url_pinned_to_a_literal_version_is_rejected
    source = @cask.sub('/v#{version}/', '/v0.1.6/')
    assert_includes errors(source).join("\n"), 'does not match'
  end

  def test_url_pinned_to_a_literal_architecture_is_rejected
    source = @cask.sub('macOS-#{arch}.zip', 'macOS-universal.zip')
    assert_includes errors(source).join("\n"), 'does not match'
  end

  # Dropping auto_updates would make a plain `brew upgrade` reinstall the app
  # underneath Sparkle, so the check has to fail loudly.
  def test_missing_auto_updates_is_rejected
    source = @cask.sub(/^  auto_updates true$/, '')
    assert_includes errors(source).join("\n"), 'auto_updates'
  end

  def test_missing_zap_path_is_rejected
    source = @cask.sub("    \"~/Library/Caches/dev.wzz.zisla\",\n", '')
    assert_includes errors(source).join("\n"), 'zap does not trash'
  end

  def test_site_on_a_different_release_is_rejected
    content = @content.sub(/^  version: '[^']*',$/, "  version: 'v9.9.9',")
    assert_includes errors(@cask, content_source: content).join("\n"), "does not match the site's latestRelease"
  end

  def test_description_repeating_the_cask_name_is_rejected
    source = @cask.sub(/^  desc ".*"$/, '  desc "zisla is a top workspace"')
    assert_includes errors(source).join("\n"), 'must not start with the cask name'
  end
end
