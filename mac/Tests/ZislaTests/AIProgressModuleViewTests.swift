import Foundation
import Testing

@Suite(.serialized)
struct AIProgressModuleViewTests {
    @Test
    func usageHistoryLoadsWithoutViewOwnedRefreshWork() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Zisla/AIProgressModuleView.swift"),
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Zisla/AppModel.swift"),
            encoding: .utf8
        )

        #expect(!viewSource.contains("TimelineView(.periodic(from: .now, by: 15))"))
        #expect(viewSource.contains("usageSummary(endingAt: .now)"))
        #expect(!viewSource.contains("monitor.refreshActiveTasks()"))
        #expect(!viewSource.contains("monitor.loadUsageHistory()"))
        #expect(!viewSource.contains("await Task.yield()"))

        guard let selectedModule = modelSource.range(of: "@Published var selectedModule") else {
            Issue.record("Could not find selectedModule in AppModel")
            return
        }
        let selectedModuleSource = modelSource[selectedModule.lowerBound...]
        guard let aiModuleCase = selectedModuleSource.range(of: "case .aiMonitor:") else {
            Issue.record("Could not find aiMonitor case")
            return
        }
        let aiModuleBlock = selectedModuleSource[aiModuleCase.lowerBound...]
        guard let defaultCase = aiModuleBlock.range(of: "default:") else {
            Issue.record("Could not find default case")
            return
        }
        let aiModuleAction = aiModuleBlock[..<defaultCase.lowerBound]

        #expect(!aiModuleAction.contains("aiMonitor.refreshActiveTasks()"))
        #expect(aiModuleAction.contains("aiMonitor.loadUsageHistory()"))

        guard let expansionRefresh = modelSource.range(of: "func refreshForExpansion()") else {
            Issue.record("Could not find refreshForExpansion in AppModel")
            return
        }
        let expansionSource = modelSource[expansionRefresh.lowerBound...]
        guard let nextFunction = expansionSource.range(of: "func refreshWeather()") else {
            Issue.record("Could not isolate refreshForExpansion in AppModel")
            return
        }
        let expansionBody = expansionSource[..<nextFunction.lowerBound]
        guard let deferredWork = expansionBody.range(of: "Task { @MainActor") else {
            Issue.record("Could not find deferred expansion work")
            return
        }
        let synchronousExpansionWork = expansionBody[..<deferredWork.lowerBound]

        #expect(!synchronousExpansionWork.contains("aiMonitor.refreshActiveTasks()"))
        #expect(expansionBody.contains("try? await Task.sleep(for: .milliseconds(250))"))
        #expect(expansionBody.contains("if settings.aiProgressEnabled, module != .aiMonitor { self.aiMonitor.refresh() }"))
    }
}
