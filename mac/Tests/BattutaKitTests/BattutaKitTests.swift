import XCTest
@testable import BattutaKit

final class BattutaKitTests: XCTestCase {
    @MainActor
    func testBattutaServiceInitialization() {
        let service = BattutaService()
        XCTAssertFalse(service.isRunning, "Service should not be running initially")
        XCTAssertNil(service.errorMessage, "Should have no error message initially")
    }

    @MainActor
    func testProfileLoading() {
        let service = BattutaService()

        // 测试加载键盘音色
        service.loadProfile(SwitchProfile.holyPanda.rawValue)

        // 测试加载鼠标音色
        let loaded = service.loadPointerProfile(PointerSoundProfile.classic.rawValue)
        XCTAssertTrue(loaded, "Should successfully load pointer profile")
    }

    func testSwitchProfileDisplayNames() {
        XCTAssertEqual(SwitchProfile.holyPanda.displayName, "Holy Panda")
        XCTAssertEqual(SwitchProfile.mxBlue.displayName, "Cherry MX Blue")
        XCTAssertEqual(SwitchProfile.topre.displayName, "Topre")
    }

    func testPointerSoundProfileDisplayNames() {
        XCTAssertEqual(PointerSoundProfile.classic.displayName, "经典微动")
        XCTAssertEqual(PointerSoundProfile.crisp.displayName, "电竞脆响")
    }

    func testKeySoundMapper() {
        // 测试空格键映射
        let spaceSample = KeySoundMapper.sample(
            for: 49,
            phase: .press,
            profile: .holyPanda
        )
        XCTAssertEqual(spaceSample, .space)

        // 测试回车键映射
        let enterSample = KeySoundMapper.sample(
            for: 36,
            phase: .press,
            profile: .holyPanda
        )
        XCTAssertEqual(enterSample, .enter)

        // 测试退格键映射
        let backspaceSample = KeySoundMapper.sample(
            for: 51,
            phase: .press,
            profile: .holyPanda
        )
        XCTAssertEqual(backspaceSample, .backspace)
    }

    func testPointerButtonSample() {
        XCTAssertEqual(PointerButton.primary.sample, .primary)
        XCTAssertEqual(PointerButton.secondary.sample, .secondary)
        XCTAssertEqual(PointerButton.middle.sample, .middle)
    }

    func testGlobalInputEventConstruction() {
        let keyboardEvent = KeyboardEvent(
            kind: .keyDown,
            keyCode: 0,
            isRepeat: false
        )
        let inputEvent = GlobalInputEvent.keyboard(keyboardEvent)

        if case .keyboard(let event) = inputEvent {
            XCTAssertEqual(event.kind, .keyDown)
            XCTAssertEqual(event.keyCode, 0)
            XCTAssertFalse(event.isRepeat)
        } else {
            XCTFail("Expected keyboard event")
        }
    }
}
