import Foundation
import Testing
@testable import ZislaCore

struct SystemMonitorMenuBarSettingsTests {
    @Test
    func newSettingsKeepIndividualIconsAndConfiguredDefaults() {
        let settings = FeatureSettings()
        #expect(settings == FeatureSettings.default)
        #expect(settings.systemMonitorMenuBarLayout == .individual)
        #expect(settings.systemMonitorMenuBarTopRow == [.cpu])
        #expect(settings.systemMonitorMenuBarBottomRow == [.gpu])
        #expect(!settings.systemMonitorMenuBarCombinedIconEnabled)
        #expect(settings.systemMonitorMenuBarCombinedIconMetric == .memory)
        #expect(settings.systemMonitorMenuBarMetrics == [.cpu])
        #expect(settings.systemMonitorMenuBarDisplayStyle == .compact)
        #expect(!settings.menuBarAppIconEnabled)
    }

    @Test
    func legacyJSONKeepsIndividualIconsAndExistingSelection() throws {
        for payload in [
            "{}",
            #"{"systemMonitorMenuBarMetrics":["gpu","memory","fan"],"systemMonitorMenuBarDisplayStyle":"detailed","menuBarAppIconEnabled":true}"#,
        ] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
            #expect(settings.systemMonitorMenuBarLayout == .individual)
            #expect(settings.systemMonitorMenuBarTopRow == [.cpu])
            #expect(settings.systemMonitorMenuBarBottomRow == [.gpu])
            #expect(!settings.systemMonitorMenuBarCombinedIconEnabled)
            #expect(settings.systemMonitorMenuBarCombinedIconMetric == .memory)
            if payload == "{}" {
                #expect(settings.systemMonitorMenuBarMetrics == [.cpu])
                #expect(settings.systemMonitorMenuBarDisplayStyle == .compact)
                #expect(!settings.menuBarAppIconEnabled)
            } else {
                #expect(settings.systemMonitorMenuBarMetrics == [.gpu, .memory, .fan])
                #expect(settings.systemMonitorMenuBarDisplayStyle == .detailed)
                #expect(settings.menuBarAppIconEnabled)
            }
        }
    }

    @Test
    func nullNewFieldsUseDefaults() throws {
        let payload = Data(#"{"systemMonitorMenuBarLayout":null,"systemMonitorMenuBarTopRow":null,"systemMonitorMenuBarBottomRow":null,"systemMonitorMenuBarCombinedIconEnabled":null,"systemMonitorMenuBarCombinedIconMetric":null,"systemMonitorMenuBarCombinedIconAppearance":null}"#.utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: payload)
        #expect(settings == FeatureSettings.default)
        #expect(settings.systemMonitorMenuBarCombinedIconMetric == .memory)
        #expect(settings.systemMonitorMenuBarCombinedIconAppearance == SystemMonitorCombinedIconAppearance(
            ringStrokeStyle: .bold,
            showsBatteryPercentage: true,
            showsChargingIndicator: true,
            showsPercentageWhenConnected: true
        ))
    }

    @Test
    func allCombinedIconSettingsRoundTrip() throws {
        for layout in SystemMonitorMenuBarLayout.allCases {
            for iconMetric in SystemMonitorCombinedIconMetric.allCases {
                for iconEnabled in [false, true] {
                    let settings = FeatureSettings(
                        systemMonitorMenuBarMetrics: [.memory, .fan],
                        systemMonitorMenuBarDisplayStyle: .detailed,
                        systemMonitorMenuBarLayout: layout,
                        systemMonitorMenuBarTopRow: [.network, .cpu],
                        systemMonitorMenuBarBottomRow: [.fan],
                        systemMonitorMenuBarCombinedIconEnabled: iconEnabled,
                        systemMonitorMenuBarCombinedIconMetric: iconMetric,
                        menuBarAppIconEnabled: true
                    )
                    let data = try JSONEncoder().encode(settings)
                    let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    #expect(payload["systemMonitorMenuBarLayout"] as? String == layout.rawValue)
                    #expect(payload["systemMonitorMenuBarTopRow"] as? [String] == ["network", "cpu"])
                    #expect(payload["systemMonitorMenuBarBottomRow"] as? [String] == ["fan"])
                    #expect(payload["systemMonitorMenuBarCombinedIconEnabled"] as? Bool == iconEnabled)
                    #expect(payload["systemMonitorMenuBarCombinedIconMetric"] as? String == iconMetric.rawValue)
                    let restored = try JSONDecoder().decode(FeatureSettings.self, from: data)
                    #expect(restored == settings)
                }
            }
        }
    }

    @Test
    func updatedSettingsRoundTripWithoutNormalizingPersistedRows() throws {
        var settings = FeatureSettings.default
        settings.systemMonitorMenuBarLayout = .stacked
        settings.systemMonitorMenuBarTopRow = [.fan, .cpu, .fan, .gpu, .network]
        settings.systemMonitorMenuBarBottomRow = [.fan, .gpu, .gpu, .memory]
        settings.systemMonitorMenuBarCombinedIconEnabled = true
        settings.systemMonitorMenuBarCombinedIconMetric = .volume
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        let rows = SystemMonitorMenuBarRows.normalized(
            top: restored.systemMonitorMenuBarTopRow,
            bottom: restored.systemMonitorMenuBarBottomRow
        )
        #expect(rows == [[.fan], [.gpu, .memory]])
        #expect(restored == settings)
        #expect(restored.systemMonitorMenuBarMetrics == [.cpu])
        #expect(restored.systemMonitorMenuBarDisplayStyle == .compact)
    }

    @Test
    func emptyPersistedRowsAreNotRewritten() throws {
        let settings = FeatureSettings(systemMonitorMenuBarTopRow: [], systemMonitorMenuBarBottomRow: [])
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(SystemMonitorMenuBarRows.normalized(
            top: restored.systemMonitorMenuBarTopRow,
            bottom: restored.systemMonitorMenuBarBottomRow
        ) == [[.cpu], [.gpu]])
        #expect(restored.systemMonitorMenuBarTopRow.isEmpty)
        #expect(restored.systemMonitorMenuBarBottomRow.isEmpty)
        #expect(restored == settings)
    }

    @Test
    func enumTitlesAndRawValuesMatchFixedInterface() {
        #expect(SystemMonitorMenuBarLayout.allCases == [.individual, .stacked, .both, .none])
        #expect(SystemMonitorMenuBarLayout.allCases.map(\.rawValue) == ["individual", "stacked", "both", "none"])
        #expect(SystemMonitorMenuBarLayout.allCases.map(\.menuTitle) == ["独立", "合并", "独立与合并", "无"])
        #expect(SystemMonitorCombinedIconMetric.allCases == [.cpu, .gpu, .memory, .volume, .brightness])
        #expect(SystemMonitorCombinedIconMetric.allCases.map(\.rawValue) == ["cpu", "gpu", "memory", "volume", "brightness"])
        #expect(SystemMonitorCombinedIconMetric.allCases.map(\.menuTitle) == ["CPU", "GPU", "内存", "音量", "屏幕亮度"])
        #expect(SystemMonitorMenuBarMetric.allCases == [.cpu, .gpu, .memory, .disk, .network, .fan])
    }

    @Test
    func ordinaryMetricsKeepTwoOrFourSlotsAndUserOrder() {
        #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu], bottom: [.gpu]) == [[.cpu], [.gpu]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [.disk, .memory], bottom: [.gpu]) == [[.disk, .memory], [.gpu, .cpu]])
        #expect(SystemMonitorMenuBarRows.adjusted(top: [.cpu], bottom: [.gpu], count: 3) == [[.cpu, .memory], [.gpu, .disk]])
        #expect(SystemMonitorMenuBarRows.availableCounts(top: [], bottom: []) == [2, 4])
    }

    @Test
    func eitherWideMetricOccupiesOneRowAndAllowsTwoOrThreeItems() {
        for wide: SystemMonitorMenuBarMetric in [.network, .fan] {
            #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu, .gpu], bottom: [wide]) == [[.cpu, .gpu], [wide]])
            #expect(SystemMonitorMenuBarRows.normalized(top: [wide, .memory], bottom: [.gpu]) == [[wide], [.gpu, .memory]])
            #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu], bottom: [.gpu, wide]) == [[.cpu, .gpu], [wide]])
            #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu, .memory], bottom: [.gpu, wide]) == [[.cpu, .memory], [wide]])
            #expect(SystemMonitorMenuBarRows.availableCounts(top: [wide], bottom: [.cpu]) == [2, 3])
            #expect(SystemMonitorMenuBarRows.adjusted(top: [wide], bottom: [.cpu], count: 3) == [[wide], [.cpu, .gpu]])
            #expect(SystemMonitorMenuBarRows.adjusted(top: [.cpu], bottom: [wide], count: 4) == [[.cpu, .gpu], [wide]])
            #expect(SystemMonitorMenuBarRows.adjusted(top: [wide], bottom: [.cpu, .gpu], count: 2) == [[wide], [.cpu]])
        }
    }

    @Test
    func bothWideMetricsUseOnlyTwoRowsEvenWhenPreviouslyGrouped() {
        for first: SystemMonitorMenuBarMetric in [.network, .fan] {
            let second: SystemMonitorMenuBarMetric = first == .network ? .fan : .network
            for (top, bottom): ([SystemMonitorMenuBarMetric], [SystemMonitorMenuBarMetric]) in [
                ([first], [second]), ([.cpu, first], [.gpu, second]),
                ([first, second], [.cpu, .gpu]), ([.cpu, .gpu], [first, second]),
            ] {
                #expect(SystemMonitorMenuBarRows.normalized(top: top, bottom: bottom) == [[first], [second]])
                #expect(SystemMonitorMenuBarRows.availableCounts(top: top, bottom: bottom) == [2])
                for count in [2, 3, 4, Int.max] {
                    #expect(SystemMonitorMenuBarRows.adjusted(top: top, bottom: bottom, count: count) == [[first], [second]])
                }
            }
        }
    }

    @Test
    func normalizationDeduplicatesTruncatesAndFillsEmptyRows() {
        #expect(SystemMonitorMenuBarRows.normalized(top: [], bottom: []) == [[.cpu], [.gpu]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [], bottom: [.cpu, .fan]) == [[.cpu, .gpu], [.fan]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [.gpu, .gpu, .cpu, .memory], bottom: [.fan]) == [[.gpu, .cpu], [.fan]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu, .gpu], bottom: [.cpu, .gpu, .cpu]) == [[.cpu, .gpu], [.memory, .disk]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu], bottom: [.cpu]) == [[.cpu], [.gpu]])
        #expect(SystemMonitorMenuBarRows.normalized(top: SystemMonitorMenuBarMetric.allCases, bottom: []) == [[.cpu, .gpu], [.memory, .disk]])
    }

    @Test
    func invalidDisplayCountsClampToSupportedBounds() {
        for count in [Int.min, -1, 0, 1] {
            #expect(SystemMonitorMenuBarRows.adjusted(top: [.cpu, .memory], bottom: [.gpu, .disk], count: count) == [[.cpu], [.gpu]])
        }
        for count in [5, Int.max] {
            #expect(SystemMonitorMenuBarRows.adjusted(top: [.cpu], bottom: [.gpu], count: count) == [[.cpu, .memory], [.gpu, .disk]])
            #expect(SystemMonitorMenuBarRows.adjusted(top: [.network], bottom: [.gpu], count: count) == [[.network], [.gpu, .cpu]])
        }
    }

    @Test
    func boundedEnumerationKeepsNormalizedAndAdjustedRowsLegal() {
        let metrics = SystemMonitorMenuBarMetric.allCases
        let inputs: [[SystemMonitorMenuBarMetric]] = [[]] + metrics.map { [$0] }
            + metrics.flatMap { first in metrics.map { [first, $0] } }
            + [metrics, Array(metrics.reversed()), Array(repeating: .fan, count: 8)]
        let budget = 7_000
        #expect(inputs.count * inputs.count * 3 <= budget)
        var combinations = 0
        for top in inputs {
            for bottom in inputs {
                let source = SystemMonitorMenuBarRows.normalized(top: top, bottom: bottom)
                let wideMetrics = Set(source.joined().filter { $0 == .network || $0 == .fan })
                let expectedCounts = wideMetrics.count == 2 ? [2] : wideMetrics.isEmpty ? [2, 4] : [2, 3]
                #expect(SystemMonitorMenuBarRows.availableCounts(top: top, bottom: bottom) == expectedCounts)
                for count in [2, 3, 4] {
                    combinations += 1
                    let adjusted = SystemMonitorMenuBarRows.adjusted(top: top, bottom: bottom, count: count)
                    let flattened = adjusted.flatMap { $0 }
                    let expectedCount = count == 2 || wideMetrics.count == 2 ? 2 : wideMetrics.isEmpty ? 4 : 3
                    #expect(adjusted.count == 2)
                    #expect(adjusted.allSatisfy { (1...2).contains($0.count) })
                    #expect(flattened.count == expectedCount)
                    #expect(Set(flattened).count == flattened.count)
                    #expect(Set(flattened.filter { $0 == .network || $0 == .fan }) == wideMetrics)
                    for row in adjusted where row.contains(.network) || row.contains(.fan) {
                        #expect(row.count == 1)
                    }
                    #expect(SystemMonitorMenuBarRows.normalized(top: adjusted[0], bottom: adjusted[1]) == adjusted)
                    #expect(SystemMonitorMenuBarRows.adjusted(top: adjusted[0], bottom: adjusted[1], count: count) == adjusted)
                    #expect(adjusted[0].first == source[0].first)
                    #expect(adjusted[1].first == source[1].first)
                }
            }
        }
        #expect(combinations == inputs.count * inputs.count * 3)
    }

    @Test
    func invalidNewSettingsAreRejected() {
        for payload in [
            #"{"systemMonitorMenuBarLayout":"unknown"}"#,
            #"{"systemMonitorMenuBarLayout":true}"#,
            #"{"systemMonitorMenuBarTopRow":"cpu"}"#,
            #"{"systemMonitorMenuBarTopRow":["unknown"]}"#,
            #"{"systemMonitorMenuBarTopRow":[null]}"#,
            #"{"systemMonitorMenuBarBottomRow":false}"#,
            #"{"systemMonitorMenuBarBottomRow":["volume"]}"#,
            #"{"systemMonitorMenuBarCombinedIconEnabled":"true"}"#,
            #"{"systemMonitorMenuBarCombinedIconMetric":"fan"}"#,
            #"{"systemMonitorMenuBarCombinedIconMetric":1}"#,
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
            }
        }
    }

    @Test
    func legacyMetricEncodingAndEmptySelectionRemainUnchanged() throws {
        for metrics: Set<SystemMonitorMenuBarMetric> in [[], Set(SystemMonitorMenuBarMetric.allCases)] {
            for style in SystemMonitorMenuBarDisplayStyle.allCases {
                let settings = FeatureSettings(systemMonitorMenuBarMetrics: metrics, systemMonitorMenuBarDisplayStyle: style)
                let data = try JSONEncoder().encode(settings)
                let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let encodedMetrics = try #require(payload["systemMonitorMenuBarMetrics"] as? [String])
                #expect(Set(encodedMetrics) == Set(metrics.map(\.rawValue)))
                #expect(payload["systemMonitorMenuBarDisplayStyle"] as? String == style.rawValue)
                let restored = try JSONDecoder().decode(FeatureSettings.self, from: data)
                #expect(restored == settings)
            }
        }
    }
}
