import Testing
import ZislaCore

@testable import Zisla

@MainActor
struct SettingsHistoryTests {
    @Test
    func initialHistoryHasNoAvailableNavigation() {
        let input = SettingsInput()
        input.settingsQuery = "PDF"
        input.weatherQuery = "上海"

        #expect(!input.canNavigate(backward: true, settings: .default))
        #expect(!input.canNavigate(backward: false, settings: .default))
        input.navigate(backward: true, settings: .default)
        input.navigate(backward: false, settings: .default)

        #expect(input.selection == .general)
        #expect(input.settingsQuery == "PDF")
        #expect(input.weatherQuery == "上海")
    }

    @Test
    func backAndForwardRestoreVisitedPagesAndStopAtBothEnds() {
        let input = SettingsInput()
        input.select(.features)
        input.select(.networkProxy)

        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .features)
        #expect(input.canNavigate(backward: true, settings: .default))
        #expect(input.canNavigate(backward: false, settings: .default))
        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .general)
        #expect(!input.canNavigate(backward: true, settings: .default))
        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .general)

        input.navigate(backward: false, settings: .default)
        #expect(input.selection == .features)
        input.navigate(backward: false, settings: .default)
        #expect(input.selection == .networkProxy)
        #expect(!input.canNavigate(backward: false, settings: .default))
        input.navigate(backward: false, settings: .default)
        #expect(input.selection == .networkProxy)
    }

    @Test
    func repeatedDestinationsDoNotAddStepsOrDiscardTheForwardBranch() {
        let input = SettingsInput()
        input.select(.features)
        input.select(.features)
        input.select(.networkProxy)
        input.navigate(backward: true, settings: .default)
        input.select(.features)

        #expect(input.canNavigate(backward: false, settings: .default))
        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .general)
        #expect(!input.canNavigate(backward: true, settings: .default))
        input.navigate(backward: false, settings: .default)
        input.navigate(backward: false, settings: .default)
        #expect(input.selection == .networkProxy)
    }

    @Test
    func aNewDestinationAfterBackDiscardsTheForwardBranch() {
        let input = SettingsInput()
        input.select(.features)
        input.select(.networkProxy)
        input.navigate(backward: true, settings: .default)
        input.select(.general, searchTarget: .row("界面语言"))

        #expect(!input.canNavigate(backward: false, settings: .default))
        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .features)
        input.navigate(backward: false, settings: .default)
        #expect(input.selection == .general)
        #expect(input.searchTarget == .row("界面语言"))
        #expect(!input.canNavigate(backward: false, settings: .default))
    }

    @Test
    func editingSearchDoesNotReplaceVisitedAnchorsOrCreateHistorySteps() {
        let input = SettingsInput()
        input.select(.general, searchTarget: .row("界面语言"))
        input.settingsQuery = "P"
        input.settingsQuery = "PD"
        input.settingsQuery = "PDF"
        input.select(.pdfTools, searchTarget: .pdfOperation(.rotate))
        input.settingsQuery = "语音"

        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .general)
        #expect(input.searchTarget == .row("界面语言"))
        #expect(input.settingsQuery.isEmpty)
        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .general)
        #expect(input.searchTarget == nil)
        #expect(!input.canNavigate(backward: true, settings: .default))

        input.navigate(backward: false, settings: .default)
        input.navigate(backward: false, settings: .default)
        #expect(input.selection == .pdfTools)
        #expect(input.selectedPDFOperation == .rotate)
    }

    @Test
    func ordinaryPDFNavigationIsDistinctFromAnOperationSearchDestination() {
        let input = SettingsInput()
        input.select(.pdfTools, searchTarget: .pdfOperation(.rotate))
        input.select(.pdfTools)
        #expect(input.selectedPDFOperation == .merge)

        input.navigate(backward: true, settings: .default)
        #expect(input.selectedPDFOperation == .rotate)
        input.navigate(backward: false, settings: .default)
        #expect(input.selectedPDFOperation == .merge)
        #expect(input.searchTarget == nil)
    }

    @Test
    func voiceSubpagesAndTheirSearchDestinationsAreRestored() {
        let input = SettingsInput()
        input.select(.voice)
        input.voicePage = .history
        input.select(.voice, searchTarget: .group("本地模型"))
        input.select(.general)

        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .voice)
        #expect(input.voicePage == .settings)
        #expect(input.searchTarget == .group("本地模型"))
        input.navigate(backward: true, settings: .default)
        #expect(input.voicePage == .history)
        #expect(input.searchTarget == nil)
        input.navigate(backward: true, settings: .default)
        #expect(input.voicePage == .settings)
        #expect(input.selection == .voice)
        input.navigate(backward: false, settings: .default)
        #expect(input.voicePage == .history)

        input.select(.voice, searchTarget: .row("录音模式"))
        input.voicePage = .history
        #expect(input.searchTarget == nil)
        input.navigate(backward: true, settings: .default)
        #expect(input.voicePage == .settings)
        #expect(input.searchTarget == .row("录音模式"))
    }

    @Test
    func directSectionAndVoicePageWritesRemainNavigable() {
        let input = SettingsInput()
        input.selection = .voice
        input.voicePage = .history
        input.selection = .general

        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .voice)
        #expect(input.voicePage == .history)
        input.navigate(backward: true, settings: .default)
        #expect(input.voicePage == .settings)
        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .general)
        #expect(!input.canNavigate(backward: true, settings: .default))

        input.select(.voice, searchTarget: .row("录音模式"))
        input.selection = .features
        #expect(input.searchTarget == nil)
    }

    @Test
    func unchangedDirectValuesPreserveTheCurrentSearchAnchor() {
        let input = SettingsInput()
        input.select(.voice, searchTarget: .row("录音模式"))
        input.selection = .voice
        input.voicePage = .settings

        #expect(input.searchTarget == .row("录音模式"))
        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .general)
        #expect(!input.canNavigate(backward: true, settings: .default))
    }

    @Test
    func visitingOtherSectionsDoesNotRestoreAnUnrelatedVoicePage() {
        let input = SettingsInput()
        input.select(.features, searchTarget: .row("语音输入"))
        input.voicePage = .history
        #expect(input.searchTarget == .row("语音输入"))

        input.navigate(backward: true, settings: .default)
        #expect(input.selection == .general)
        #expect(input.voicePage == .history)
        input.navigate(backward: false, settings: .default)
        #expect(input.selection == .features)
        #expect(input.searchTarget == .row("语音输入"))
        #expect(input.voicePage == .history)
        #expect(!input.canNavigate(backward: false, settings: .default))
    }

    @Test
    func hiddenFeaturePagesAreSkippedInBothDirections() {
        let input = SettingsInput()
        input.select(.voice, searchTarget: .group("本地模型"))
        input.select(.pdfTools, searchTarget: .pdfOperation(.rotate))
        input.select(.features)
        var settings = FeatureSettings.default
        settings.voiceInputEnabled = false
        settings.pdfToolsEnabled = false

        input.navigate(backward: true, settings: settings)
        #expect(input.selection == .general)
        #expect(!input.canNavigate(backward: true, settings: settings))
        #expect(input.canNavigate(backward: false, settings: settings))
        input.navigate(backward: false, settings: settings)
        #expect(input.selection == .features)
        #expect(!input.canNavigate(backward: false, settings: settings))
    }

    @Test
    func hiddenPagesDoNotLeaveAnEnabledButtonThatReturnsToTheCurrentDestination() {
        let input = SettingsInput()
        input.select(.voice)
        input.select(.general)
        var settings = FeatureSettings.default
        settings.voiceInputEnabled = false

        #expect(!input.canNavigate(backward: true, settings: settings))
        input.settingsQuery = "界面语言"
        input.navigate(backward: true, settings: settings)
        #expect(input.selection == .general)
        #expect(input.settingsQuery == "界面语言")
    }

    @Test
    func collapsingTheSidebarPreservesNavigationAndUnrelatedInput() {
        let input = SettingsInput()
        input.select(.voice)
        input.voicePage = .history
        input.select(.features)
        input.weatherQuery = "上海"
        #expect(input.isSidebarVisible)

        input.isSidebarVisible.toggle()
        input.navigate(backward: true, settings: .default)
        #expect(!input.isSidebarVisible)
        #expect(input.selection == .voice)
        #expect(input.voicePage == .history)
        #expect(input.weatherQuery == "上海")
        input.isSidebarVisible.toggle()
        #expect(input.isSidebarVisible)
        #expect(input.canNavigate(backward: false, settings: .default))
    }
}
