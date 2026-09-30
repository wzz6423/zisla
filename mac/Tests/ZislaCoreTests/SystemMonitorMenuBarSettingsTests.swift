import Foundation
import Testing
@testable import ZislaCore

struct SystemMonitorMenuBarSettingsTests {
    @Test
    func newSettingsKeepIndividualIconsAndOriginalDefaults() {
        let settings = FeatureSettings()
        #expect(settings == FeatureSettings.default)
        #expect(settings.systemMonitorMenuBarLayout == .individual)
        #expect(settings.systemMonitorMenuBarTopRow == [.cpu])
        #expect(settings.systemMonitorMenuBarBottomRow == [.gpu])
        #expect(!settings.systemMonitorMenuBarCombinedIconEnabled)
        #expect(settings.systemMonitorMenuBarCombinedIconMetric == .cpu)
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
            #expect(settings.systemMonitorMenuBarCombinedIconMetric == .cpu)
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
        let payload = Data(#"{"systemMonitorMenuBarLayout":null,"systemMonitorMenuBarTopRow":null,"systemMonitorMenuBarBottomRow":null,"systemMonitorMenuBarCombinedIconEnabled":null,"systemMonitorMenuBarCombinedIconMetric":null}"#.utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: payload)
        #expect(settings == FeatureSettings.default)
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
        #expect(rows == [[.fan, .cpu], [.gpu]])
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
        #expect(SystemMonitorMenuBarLayout.allCases == [.individual, .stacked])
        #expect(SystemMonitorMenuBarLayout.allCases.map(\.rawValue) == ["individual", "stacked"])
        #expect(SystemMonitorMenuBarLayout.allCases.map(\.menuTitle) == ["独立", "合并"])
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
    func normalizationPreservesAnyUserOrder() {
        for first in SystemMonitorMenuBarMetric.allCases {
            for second in SystemMonitorMenuBarMetric.allCases where second != first {
                for third in SystemMonitorMenuBarMetric.allCases where third != first && third != second {
                    #expect(SystemMonitorMenuBarRows.normalized(top: [first, second], bottom: [third]) == [[first, second], [third]])
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
    func bottomSkipsTopMetricsAndKeepsFirstAvailable() {
        #expect(SystemMonitorMenuBarRows.normalized(
            top: [.fan, .memory],
            bottom: [.fan, .memory, .network, .disk, .gpu, .network]
        ) == [[.fan, .memory], [.network]])
    }

    @Test
    func overfullRowsAreLimitedToTwoAndOneMetrics() {
        #expect(SystemMonitorMenuBarRows.normalized(
            top: SystemMonitorMenuBarMetric.allCases,
            bottom: Array(SystemMonitorMenuBarMetric.allCases.reversed())
        ) == [[.cpu, .gpu], [.fan]])
        #expect(SystemMonitorMenuBarRows.normalized(
            top: [.fan, .gpu, .memory],
            bottom: [.memory, .cpu, .disk]
        ) == [[.fan, .gpu], [.memory]])
    }

    @Test
    func emptyRowsUseDefaultTopAndFirstAvailableBottom() {
        #expect(SystemMonitorMenuBarRows.normalized(top: [], bottom: []) == [[.cpu], [.gpu]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [], bottom: [.cpu, .fan]) == [[.cpu], [.fan]])
    }

    @Test
    func fullyRepeatedBottomUsesFirstMetricAbsentFromTop() {
        #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu, .gpu], bottom: [.cpu, .gpu, .cpu]) == [[.cpu, .gpu], [.memory]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [.cpu], bottom: [.cpu]) == [[.cpu], [.gpu]])
        #expect(SystemMonitorMenuBarRows.normalized(top: [.gpu, .memory], bottom: [.gpu, .memory]) == [[.gpu, .memory], [.cpu]])
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
                #expect(rows[1].count == 1)
                let flattened = rows.flatMap { $0 }
                #expect(Set(flattened).count == flattened.count)
                #expect(SystemMonitorMenuBarRows.normalized(top: rows[0], bottom: rows[1]) == rows)
            }
        }
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
