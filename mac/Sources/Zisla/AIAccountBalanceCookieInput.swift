import SwiftUI
import ZislaCore
import ZislaKit

struct AIAccountBalanceCookieInput: View {
    let website: AIAccountBalanceWebsite
    let didChange: @MainActor () -> Void
    @State private var cookie = ""
    @State private var isSaving = false
    @State private var statusKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Link(AppLocalization.text(website.title), destination: website.dashboard)
                    .frame(width: 100, alignment: .leading)
                SecureField(AppLocalization.text("粘贴网站 Cookie"), text: $cookie).textFieldStyle(.roundedBorder)
                Button(AppLocalization.text("保存")) { save(removing: false) }.disabled(cookie.isEmpty || isSaving)
                Button(AppLocalization.text("清除")) { save(removing: true) }.disabled(isSaving)
            }
            if let statusKey { AppLocalizedText(statusKey).foregroundStyle(.secondary) }
        }
        .font(.system(size: 11)).padding(.vertical, 6)
    }

    private func save(removing: Bool) {
        let value = cookie
        let website = website
        isSaving = true
        statusKey = nil
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                do {
                    let store = AIAccountBalanceCookieStore()
                    if removing { try store.removeCookie(for: website) }
                    else { try store.setCookie(value, for: website) }
                    return true
                } catch { return false }
            }.value
            isSaving = false
            if result {
                cookie = ""
                statusKey = removing ? "额度查询凭据已清除" : "额度查询凭据已保存"
                didChange()
            } else { statusKey = "无法保存额度查询凭据，请检查 Cookie 格式或存储权限" }
        }
    }
}
