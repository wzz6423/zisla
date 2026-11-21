import SwiftUI
import ZislaCore
import ZislaKit

struct AIAccountBalanceCookieInput: View {
    @ObservedObject var input: AIAccountBalanceCookieInputModel
    let didChange: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Link(AppLocalization.text(input.website.title), destination: input.website.dashboard)
                    .frame(width: 100, alignment: .leading)
                SecureField(AppLocalization.text("粘贴网站 Cookie"), text: $input.cookie).textFieldStyle(.roundedBorder)
                    .disabled(input.isSaving)
                Button(AppLocalization.text("从默认浏览器导入")) { perform(.importBrowser) }.disabled(input.isSaving)
                    .keepsIntrinsicWidth()
                Button(AppLocalization.text("保存")) { perform(.save) }.disabled(input.cookie.isEmpty || input.isSaving)
                    .keepsIntrinsicWidth()
                Button(AppLocalization.text("清除")) { perform(.remove) }.disabled(input.isSaving)
                    .keepsIntrinsicWidth()
            }
            if let statusKey = input.statusKey { AppLocalizedText(statusKey).foregroundStyle(.secondary) }
        }
        .font(.system(size: 11)).padding(.vertical, 6)
    }

    private func perform(_ action: AIAccountBalanceCookieInputModel.Action) {
        Task { await input.perform(action, didChange: didChange) }
    }
}

@MainActor
final class AIAccountBalanceCookieInputModel: ObservableObject {
    enum Action: Sendable { case save, remove, importBrowser }

    let website: AIAccountBalanceWebsite
    @Published var cookie = ""
    @Published private(set) var isSaving = false
    @Published private(set) var statusKey: String?
    private let importCookie: @Sendable (AIAccountBalanceWebsite) throws -> Void
    private let saveCookie: @Sendable (String, AIAccountBalanceWebsite, Bool) throws -> Void

    init(website: AIAccountBalanceWebsite, importCookie: @escaping @Sendable (AIAccountBalanceWebsite) throws -> Void = {
        try AIAccountBalanceBrowserCookieImporter().importCookie(for: $0)
    }, saveCookie: @escaping @Sendable (String, AIAccountBalanceWebsite, Bool) throws -> Void = { value, website, removing in
        let store = AIAccountBalanceCookieStore()
        if removing { try store.removeCookie(for: website) }
        else { try store.setCookie(value, for: website) }
    }) {
        self.website = website
        self.importCookie = importCookie
        self.saveCookie = saveCookie
    }

    /// Keep one mutation in flight per website and retain manual input until persistence succeeds.
    func perform(_ action: Action, didChange: @MainActor () -> Void) async {
        guard !isSaving else { return }
        let website = website
        let value = cookie
        let importCookie = importCookie
        let saveCookie = saveCookie
        isSaving = true
        statusKey = action == .importBrowser ? "正在读取默认浏览器 Cookie" : nil
        let failure = await Task.detached(priority: .utility) { () -> String? in
            do {
                switch action {
                case .importBrowser: try importCookie(website)
                case .save: try saveCookie(value, website, false)
                case .remove: try saveCookie(value, website, true)
                }
                return nil
            } catch let error as AIAccountBalanceBrowserCookieError { return error.statusKey }
            catch { return "无法保存额度查询凭据，请检查 Cookie 格式或存储权限" }
        }.value
        isSaving = false
        if let failure { statusKey = failure }
        else {
            cookie = ""
            statusKey = action == .remove ? "额度查询凭据已清除" : "额度查询凭据已保存"
            didChange()
        }
    }
}
