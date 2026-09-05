#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

require_relative 'appcast-feeds'

class AppcastFeedsTest < Minitest::Test
  TAG = 'v0.1.7'

  # Serves whatever body each URL is mapped to, so the assertions never touch the network.
  class StubFetcher
    def initialize(bodies)
      @bodies = bodies
    end

    def call(url)
      body = @bodies[url]
      body.nil? ? [404, ''] : [200, body]
    end
  end

  def feed(host:, architecture:, tag: TAG, signature: 'c2lnbmF0dXJl', build: '15')
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel>
          <item>
            <sparkle:version>#{build}</sparkle:version>
            <enclosure url="https://#{host}.com/wzz6423/zisla/releases/download/#{tag}/zisla-#{tag}-macOS-#{architecture}.zip"
              length="1" type="application/octet-stream" sparkle:edSignature="#{signature}" />
          </item>
        </channel>
      </rss>
    XML
  end

  def bodies(channel: 'release', **overrides)
    roots = AppcastFeeds::FEED_ROOTS.fetch(channel)
    mapped = roots.flat_map do |host, root|
      AppcastFeeds::ARCHIVES.map do |name, architecture|
        ["#{root}/#{name}", feed(host: host, architecture: architecture)]
      end
    end.to_h
    mapped.merge(overrides)
  end

  def errors(bodies, channel: 'release')
    AppcastFeeds::Verifier.new(
      tag: TAG, channel: channel, fetcher: StubFetcher.new(bodies)
    ).run
  end

  def test_six_matching_feeds_pass
    assert_empty errors(bodies)
    assert_empty errors(bodies(channel: 'preview'), channel: 'preview')
  end

  def test_every_feed_is_checked
    assert_equal 6, bodies.length
  end

  # The failure this guards is the one that broke every release before 0.1.7: an
  # architecture's appcast never got uploaded, so that install 404s on both feeds.
  def test_missing_feed_is_reported
    incomplete = bodies
    missing = incomplete.keys.find { |url| url.end_with?('appcast-arm64.xml') }
    incomplete.delete(missing)
    assert_includes errors(incomplete).join("\n"), 'returned HTTP 404'
  end

  def test_feed_pointing_at_another_version_is_reported
    root = AppcastFeeds::FEED_ROOTS.fetch('release').fetch('github')
    stale = bodies("#{root}/appcast.xml" => feed(host: 'github', architecture: 'universal', tag: 'v0.1.6'))
    assert_includes errors(stale).join("\n"), 'instead of'
  end

  # A GitHub feed handing out a Gitee URL breaks the fallback: the retry lands on the
  # site that just failed.
  def test_feed_pointing_at_the_other_site_is_reported
    root = AppcastFeeds::FEED_ROOTS.fetch('release').fetch('github')
    crossed = bodies("#{root}/appcast.xml" => feed(host: 'gitee', architecture: 'universal'))
    assert_includes errors(crossed).join("\n"), 'instead of'
  end

  def test_feed_offering_another_architecture_is_reported
    root = AppcastFeeds::FEED_ROOTS.fetch('release').fetch('gitee')
    swapped = bodies("#{root}/appcast-arm64.xml" => feed(host: 'gitee', architecture: 'x86_64'))
    assert_includes errors(swapped).join("\n"), 'instead of'
  end

  def test_unsigned_feed_is_reported
    root = AppcastFeeds::FEED_ROOTS.fetch('release').fetch('gitee')
    unsigned = bodies("#{root}/appcast.xml" => feed(host: 'gitee', architecture: 'universal', signature: ''))
    assert_includes errors(unsigned).join("\n"), 'no sparkle:edSignature'
  end

  def test_multi_item_feed_is_reported
    root = AppcastFeeds::FEED_ROOTS.fetch('release').fetch('github')
    doubled = feed(host: 'github', architecture: 'universal') * 2
    assert_includes errors(bodies("#{root}/appcast.xml" => doubled)).join("\n"), '<item> elements'
  end

  def test_unknown_channel_is_rejected
    assert_raises(AppcastFeeds::VerificationError) { errors(bodies, channel: 'nightly') }
  end

  def test_unknown_host_is_rejected
    error = assert_raises(AppcastFeeds::VerificationError) do
      AppcastFeeds::Verifier.new(
        tag: TAG, channel: 'release', fetcher: StubFetcher.new(bodies), hosts: %w[giteee]
      ).run
    end
    assert_includes error.message, 'giteee'
  end

  def test_empty_host_list_is_rejected
    assert_raises(AppcastFeeds::VerificationError) do
      AppcastFeeds::Verifier.new(
        tag: TAG, channel: 'release', fetcher: StubFetcher.new(bodies), hosts: []
      ).run
    end
  end

  # A mirror that never answers has to fail with its reason attached; the workflow decides
  # whether an unreachable Gitee is a hard failure from that text.
  def test_unreachable_feed_reports_the_reason
    unreachable = ->(_url) { [0, 'SocketError: getaddrinfo failed'] }
    reported = AppcastFeeds::Verifier.new(
      tag: TAG, channel: 'release', fetcher: unreachable, hosts: %w[gitee]
    ).run
    assert_equal 3, reported.length
    assert_includes reported.join("\n"), 'could not be read: SocketError'
  end

  def test_a_single_host_can_be_verified_alone
    single = AppcastFeeds::Verifier.new(
      tag: TAG, channel: 'release', fetcher: StubFetcher.new(bodies), hosts: %w[github]
    ).run
    assert_empty single
  end

  def assets(layout: 'version', tag: TAG)
    AppcastFeeds.required_assets(tag: tag, layout: layout)
  end

  def missing(names, layout: 'version')
    AppcastFeeds.missing_assets(tag: TAG, layout: layout, names: names)
  end

  # Three appcasts plus a DMG, ZIP and checksum for each of the three architectures.
  def test_a_complete_release_carries_fifteen_assets
    assert_equal 15, assets.length
    assert_empty missing(assets)
  end

  def test_screenshots_and_source_archives_do_not_count_as_missing
    extra = assets + ["zisla-#{TAG}-screenshot.png", "zisla-#{TAG}.tar.gz"]
    assert_empty missing(extra)
  end

  # The 0.1.7 release was the one where an architecture's appcast never got uploaded.
  def test_a_missing_appcast_is_reported
    assert_equal ['appcast-x86_64.xml'], missing(assets - ['appcast-x86_64.xml'])
  end

  def test_a_missing_archive_or_checksum_is_reported
    incomplete = assets - ["zisla-#{TAG}-macOS-x86_64.zip", "zisla-#{TAG}-macOS-arm64.dmg.sha256"]
    assert_equal 2, missing(incomplete).length
  end

  # The permanent feed release hosts appcasts only; demanding archives there would fail it forever.
  def test_the_permanent_feed_release_needs_only_the_three_appcasts
    assert_equal AppcastFeeds::ARCHIVES.keys.sort, assets(layout: 'feed').sort
    assert_empty missing(assets(layout: 'feed'), layout: 'feed')
    assert_equal ['appcast-arm64.xml'], missing(%w[appcast.xml appcast-x86_64.xml], layout: 'feed')
  end

  def test_unknown_layout_is_rejected
    assert_raises(AppcastFeeds::VerificationError) { assets(layout: 'nightly') }
  end

  # gh release view emits one name per line, so trailing newlines must not read as names.
  def test_asset_names_are_read_from_untrimmed_lines
    lines = assets.map { |name| "#{name}\n" } + ["\n", "  \n"]
    assert_empty missing(lines)
  end
end
