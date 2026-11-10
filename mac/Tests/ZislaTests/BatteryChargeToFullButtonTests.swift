import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

struct BatteryChargeToFullButtonTests {
    @Test
    func fullChargeActionAndFailureUseTheRequestedLocale() {
        #expect(BatteryLocalization.string("立即充至100%", locale: Locale(identifier: "en")) == "Charge to 100% Now")
        #expect(BatteryLocalization.string("立即充至100%", locale: Locale(identifier: "zh-Hans")) == "立即充至100%")
        #expect(BatteryLocalization.string("立即充至100%", locale: Locale(identifier: "ar")) == "الشحن إلى 100% الآن")
        #expect(BatteryLocalization.string("无法立即充至100%，请重试。", locale: Locale(identifier: "en"))
            == "Couldn't charge to 100% now. Please try again.")
    }

    @Test(arguments: AppLanguage.allCases) @MainActor
    func buttonFitsTheExistingCompactHeaderInEveryLanguage(language: AppLanguage) throws {
        let renderer = ImageRenderer(content: BatteryChargeToFullButton.chargeButton(
            isRequesting: false, locale: language.locale, action: {}
        ).environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .fixedSize())
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.height <= 52, "Keep the action in the existing compact row")
        #expect(image.width > 80 && image.width <= 390, "Keep the complete translated label within the header")
    }
}
