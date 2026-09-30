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
        #expect(rows == [[.fan, .cpu], [.gpu, .memory]])
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
    func threeMetricCombinationUsesCpuAndGpuAboveFan() {
        #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu, .gpu], bottom: [.fan]) == [[.cpu, .gpu], [.fan]])
    }

    @Test
    func threeNonFanMetricsFillToFourWithoutDiscardingSelections() {
        #expect(SystemMonitorMenuBarRows.normalized(
            top: [.network, .memory],
            bottom: [.disk]
        ) == [[.network, .memory], [.disk, .cpu]])
        #expect(SystemMonitorMenuBarRows.normalized(
            top: [.disk],
            bottom: [.network, .memory]
        ) == [[.disk, .cpu], [.network, .memory]])
    }

    @Test
    func normalizationPreservesAnyUserOrder() {
        for first in SystemMonitorMenuBarMetric.allCases {
            for second in SystemMonitorMenuBarMetric.allCases where second != first {
                for third in SystemMonitorMenuBarMetric.allCases where third != first && third != second {
                    if [first, second, third].contains(.fan) {
                        #expect(SystemMonitorMenuBarRows.normalized(top: [first, second], bottom: [third]) == [[first, second], [third]])
                        #expect(SystemMonitorMenuBarRows.normalized(top: [first], bottom: [second, third]) == [[first], [second, third]])
                    }
                    for fourth in SystemMonitorMenuBarMetric.allCases where ![first, second, third].contains(fourth) {
                        #expect(SystemMonitorMenuBarRows.normalized(
                            top: [first, second],
                            bottom: [third, fourth]
                        ) == [[first, second], [third, fourth]])
                    }
                }
            }
        }
    }

    @Test
    func topDuplicatesAreRemovedBeforeTruncation() {
        #expect(SystemMonitorMenuBarRows.normalized(
            top: [.gpu, .gpu, .cpu, .cpu, .memory],
            bottom: [.fan]
        ) == [[.gpu, .cpu], [.fan]])
    }

    @Test
    func bottomSkipsTopMetricsAndDuplicatesBeforeTruncation() {
        #expect(SystemMonitorMenuBarRows.normalized(
            top: [.fan, .memory],
            bottom: [.fan, .memory, .network, .disk, .gpu, .network]
        ) == [[.fan, .memory], [.network, .disk]])
        #expect(SystemMonitorMenuBarRows.normalized(
            top: [.cpu],
            bottom: [.fan, .fan, .memory]
        ) == [[.cpu], [.fan, .memory]])
    }

    @Test
    func overfullRowsAreLimitedToTwoMetricsEach() {
        #expect(SystemMonitorMenuBarRows.normalized(
            top: SystemMonitorMenuBarMetric.allCases,
            bottom: Array(SystemMonitorMenuBarMetric.allCases.reversed())
        ) == [[.cpu, .gpu], [.fan, .network]])
        #expect(SystemMonitorMenuBarRows.normalized(
            top: [.fan, .gpu, .memory],
            bottom: [.memory, .cpu, .disk]
        ) == [[.fan, .gpu], [.memory, .cpu]])
    }

    @Test
    func emptyRowsUseDefaultTopAndFirstAvailableBottom() {
        #expect(SystemMonitorMenuBarRows.normalized(top: [], bottom: []) == [[.cpu], [.gpu]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [], bottom: [.cpu, .fan]) == [[.gpu], [.cpu, .fan]])
    }

    @Test
    func fullyRepeatedBottomUsesFirstMetricAbsentFromTop() {
        #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu, .gpu], bottom: [.cpu, .gpu, .cpu]) == [[.cpu, .gpu], [.memory, .disk]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu], bottom: [.cpu]) == [[.cpu], [.gpu]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [.gpu, .memory], bottom: [.gpu, .memory]) == [[.gpu, .memory], [.cpu, .disk]])
    }

    @Test
    func normalizationKeepsRowsNonemptyUniqueAndIdempotent() {
        let metrics = SystemMonitorMenuBarMetric.allCases
        let inputs: [[SystemMonitorMenuBarMetric]] = [[], metrics, Array(metrics.reversed())]
            + metrics.map { [$0] }
            + metrics.map { [$0, $0, $0] }
        for top in inputs {
            for bottom in inputs {
                let rows = SystemMonitorMenuBarRows.normalized(top: top, bottom: bottom)
                #expect(rows.count == 2)
                #expect((1...2).contains(rows[0].count))
                #expect((1...2).contains(rows[1].count))
                let flattened = rows.flatMap { $0 }
                #expect(Set(flattened).count == flattened.count)
                #expect([2, 4].contains(flattened.count) || (flattened.count == 3 && flattened.contains(.fan)))
                #expect(!flattened.contains(.fan) || (top + bottom).contains(.fan))
                #expect(SystemMonitorMenuBarRows.normalized(top: rows[0], bottom: rows[1]) == rows)
            }
        }
    }

    @Test
    func displayCountOptionsOnlyOfferThreeWhenFanIsSelected() {
        #expect(SystemMonitorMenuBarRows.availableCounts(top: [], bottom: []) == [2, 4])
        #expect(SystemMonitorMenuBarRows.availableCounts(top: [.cpu, .gpu], bottom: [.memory]) == [2, 4])
        #expect(SystemMonitorMenuBarRows.availableCounts(top: [.fan], bottom: [.gpu]) == [2, 3, 4])
        #expect(SystemMonitorMenuBarRows.availableCounts(top: [.cpu, .gpu], bottom: [.memory, .fan]) == [2, 3, 4])
    }

    @Test
    func changingCountKeepsRowLeadersAndFillsWithoutFan() {
        let expanded = SystemMonitorMenuBarRows.adjusted(top: [.cpu], bottom: [.gpu], count: 4)
        #expect(expanded == [[.cpu, .memory], [.gpu, .disk]])
        #expect(SystemMonitorMenuBarRows.adjusted(top: expanded[0], bottom: expanded[1], count: 2) == [[.cpu], [.gpu]])
        #expect(SystemMonitorMenuBarRows.adjusted(top: [.fan], bottom: [.network], count: 4) == [[.fan, .cpu], [.network, .gpu]])
        #expect(SystemMonitorMenuBarRows.adjusted(top: [.network], bottom: [.fan], count: 2) == [[.network], [.fan]])
    }

    @Test
    func changingCountToThreePreservesFanInItsSelectedRow() {
        for top: [SystemMonitorMenuBarMetric] in [[.cpu, .fan], [.fan, .cpu]] {
            #expect(SystemMonitorMenuBarRows.adjusted(
                top: top,
                bottom: [.memory, .network],
                count: 3
            ) == [[.fan], [.memory, .network]])
        }
        for bottom: [SystemMonitorMenuBarMetric] in [[.cpu, .fan], [.fan, .cpu]] {
            #expect(SystemMonitorMenuBarRows.adjusted(
                top: [.memory, .network],
                bottom: bottom,
                count: 3
            ) == [[.memory, .network], [.fan]])
        }
        #expect(SystemMonitorMenuBarRows.adjusted(top: [.fan], bottom: [.network], count: 3) == [[.fan], [.network, .cpu]])
        #expect(SystemMonitorMenuBarRows.adjusted(top: [.network], bottom: [.fan], count: 3) == [[.network, .cpu], [.fan]])
        #expect(SystemMonitorMenuBarRows.adjusted(top: [.fan, .memory], bottom: [.network], count: 3) == [[.fan, .memory], [.network]])
        #expect(SystemMonitorMenuBarRows.adjusted(top: [.network], bottom: [.memory, .fan], count: 3) == [[.network], [.memory, .fan]])
    }

    @Test
    func requestingThreeWithoutFanFillsToFourInstead() {
        #expect(SystemMonitorMenuBarRows.adjusted(
            top: [.network, .memory],
            bottom: [.disk],
            count: 3
        ) == [[.network, .memory], [.disk, .cpu]])
        #expect(SystemMonitorMenuBarRows.adjusted(top: [.cpu], bottom: [.gpu], count: 3) == [[.cpu, .memory], [.gpu, .disk]])
    }

    @Test
    func invalidDisplayCountsClampToSupportedBounds() {
        for count in [Int.min, -1, 0, 1] {
            #expect(SystemMonitorMenuBarRows.adjusted(
                top: [.cpu, .memory],
                bottom: [.gpu, .disk],
                count: count
            ) == [[.cpu], [.gpu]])
        }
        for count in [5, Int.max] {
            #expect(SystemMonitorMenuBarRows.adjusted(top: [.cpu], bottom: [.gpu], count: count) == [[.cpu, .memory], [.gpu, .disk]])
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
                let hasFan = source.joined().contains(.fan)
                #expect(SystemMonitorMenuBarRows.availableCounts(top: top, bottom: bottom) == (hasFan ? [2, 3, 4] : [2, 4]))
                for count in [2, 3, 4] {
                    combinations += 1
                    let adjusted = SystemMonitorMenuBarRows.adjusted(top: top, bottom: bottom, count: count)
                    let flattened = adjusted.flatMap { $0 }
                    #expect(adjusted.count == 2)
                    #expect(adjusted.allSatisfy { (1...2).contains($0.count) })
                    #expect(flattened.count == (count == 3 && !hasFan ? 4 : count))
                    #expect(Set(flattened).count == flattened.count)
                    #expect(!flattened.contains(.fan) || hasFan)
                    #expect(SystemMonitorMenuBarRows.normalized(top: adjusted[0], bottom: adjusted[1]) == adjusted)
                    #expect(SystemMonitorMenuBarRows.adjusted(top: adjusted[0], bottom: adjusted[1], count: count) == adjusted)
                    if count == 3 && hasFan {
                        #expect(adjusted[0].contains(.fan) == source[0].contains(.fan))
                        #expect(adjusted[1].contains(.fan) == source[1].contains(.fan))
                    } else if count != 3 {
                        #expect(adjusted[0].first == source[0].first)
                        #expect(adjusted[1].first == source[1].first)
                    }
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
