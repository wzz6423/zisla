import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct ContextNoteReminderLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func everyLanguageTranslatesTheRuntimeReminderKeys(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/ContextNoteViews.swift"), encoding: .utf8)
        let calls = try NSRegularExpression(pattern: #"AppLocalization\.string\("([^"]+)""#)
        let matches = calls.matches(in: source, range: NSRange(source.startIndex..., in: source))
        let keys = Set(matches.compactMap { match -> String? in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        }).union(ContextNoteReminderInterval.allCases.map(\.localizationKey)).union(["添加时间"])
        let table = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")), format: nil
        ) as? [String: String])
        let translations: [String: [String]] = [
            "zh-Hans": ["主动提醒", "不主动提醒", "每 1 小时", "每 1.5 小时", "每 3 小时", "每 6 小时", "每 12 小时", "每 1 天", "每 2 天", "每 3 天", "添加时间"],
            "zh-Hant": ["主動提醒", "不主動提醒", "每 1 小時", "每 1.5 小時", "每 3 小時", "每 6 小時", "每 12 小時", "每 1 天", "每 2 天", "每 3 天", "加入時間"],
            "en": ["Proactive reminder", "No proactive reminder", "Every 1 hour", "Every 1.5 hours", "Every 3 hours", "Every 6 hours", "Every 12 hours", "Every 1 day", "Every 2 days", "Every 3 days", "Added at"],
            "ja": ["定期リマインダー", "定期リマインダーなし", "1時間ごと", "1.5時間ごと", "3時間ごと", "6時間ごと", "12時間ごと", "1日ごと", "2日ごと", "3日ごと", "追加日時"],
            "ko": ["정기 알림", "정기 알림 없음", "1시간마다", "1.5시간마다", "3시간마다", "6시간마다", "12시간마다", "1일마다", "2일마다", "3일마다", "추가 시간"],
            "fr": ["Rappel périodique", "Aucun rappel périodique", "Toutes les heures", "Toutes les 1,5 heures", "Toutes les 3 heures", "Toutes les 6 heures", "Toutes les 12 heures", "Tous les jours", "Tous les 2 jours", "Tous les 3 jours", "Ajouté le"],
            "de": ["Regelmäßige Erinnerung", "Keine regelmäßige Erinnerung", "Jede Stunde", "Alle 1,5 Stunden", "Alle 3 Stunden", "Alle 6 Stunden", "Alle 12 Stunden", "Jeden Tag", "Alle 2 Tage", "Alle 3 Tage", "Hinzugefügt am"],
            "es": ["Recordatorio periódico", "Sin recordatorio periódico", "Cada hora", "Cada 1,5 horas", "Cada 3 horas", "Cada 6 horas", "Cada 12 horas", "Cada día", "Cada 2 días", "Cada 3 días", "Añadido el"],
            "pt-BR": ["Lembrete periódico", "Sem lembrete periódico", "A cada hora", "A cada 1,5 horas", "A cada 3 horas", "A cada 6 horas", "A cada 12 horas", "A cada dia", "A cada 2 dias", "A cada 3 dias", "Adicionado em"],
            "it": ["Promemoria periodico", "Nessun promemoria periodico", "Ogni ora", "Ogni 1,5 ore", "Ogni 3 ore", "Ogni 6 ore", "Ogni 12 ore", "Ogni giorno", "Ogni 2 giorni", "Ogni 3 giorni", "Aggiunto il"],
            "nl": ["Periodieke herinnering", "Geen periodieke herinnering", "Elk uur", "Elke 1,5 uur", "Elke 3 uur", "Elke 6 uur", "Elke 12 uur", "Elke dag", "Elke 2 dagen", "Elke 3 dagen", "Toegevoegd op"],
            "ru": ["Регулярное напоминание", "Без регулярных напоминаний", "Каждый час", "Каждые 1,5 часа", "Каждые 3 часа", "Каждые 6 часов", "Каждые 12 часов", "Каждый день", "Каждые 2 дня", "Каждые 3 дня", "Добавлено"],
            "ar": ["تذكير دوري", "بدون تذكير دوري", "كل ساعة", "كل ساعة ونصف", "كل 3 ساعات", "كل 6 ساعات", "كل 12 ساعة", "كل يوم", "كل يومين", "كل 3 أيام", "وقت الإضافة"],
            "th": ["การเตือนเป็นระยะ", "ไม่เตือนเป็นระยะ", "ทุก 1 ชั่วโมง", "ทุก 1.5 ชั่วโมง", "ทุก 3 ชั่วโมง", "ทุก 6 ชั่วโมง", "ทุก 12 ชั่วโมง", "ทุก 1 วัน", "ทุก 2 วัน", "ทุก 3 วัน", "เวลาที่เพิ่ม"],
            "id": ["Pengingat berkala", "Tanpa pengingat berkala", "Setiap 1 jam", "Setiap 1,5 jam", "Setiap 3 jam", "Setiap 6 jam", "Setiap 12 jam", "Setiap 1 hari", "Setiap 2 hari", "Setiap 3 hari", "Ditambahkan pada"],
            "vi": ["Nhắc nhở định kỳ", "Không nhắc nhở định kỳ", "Mỗi 1 giờ", "Mỗi 1,5 giờ", "Mỗi 3 giờ", "Mỗi 6 giờ", "Mỗi 12 giờ", "Mỗi 1 ngày", "Mỗi 2 ngày", "Mỗi 3 ngày", "Thời gian thêm"],
            "tr": ["Düzenli hatırlatma", "Düzenli hatırlatma yok", "Her saat", "Her 1,5 saatte", "Her 3 saatte", "Her 6 saatte", "Her 12 saatte", "Her gün", "Her 2 günde", "Her 3 günde", "Eklenme zamanı"],
        ]
        #expect(Set(translations.keys) == Set(AppLanguage.allCases.map(\.rawValue)))
        let orderedKeys = ["主动提醒"] + ContextNoteReminderInterval.allCases.map(\.localizationKey) + ["添加时间"]
        let expected = try #require(translations[language.rawValue])
        #expect(expected.count == orderedKeys.count)
        for (key, value) in zip(orderedKeys, expected) {
            #expect(table[key] == value, "Missing or incorrect \(language.rawValue) translation for \(key)")
            #expect(AppLocalization.string(key, locale: language.locale) == value)
        }
        for key in keys {
            let value = try #require(table[key], "Missing \(language.rawValue) runtime key: \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
        }
    }

    @MainActor
    @Test(.serialized, arguments: [false, true], [AppLanguage.simplifiedChinese, .english, .arabic])
    func reminderPickerIsOnlyAvailableForSavedNoteDetails(saved: Bool, language: AppLanguage) async throws {
        _ = NSApplication.shared
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let draft = ContextNoteDraft(location: .desktop(displayID: "fixture", displayName: "Screen"))
        draft.text = "Synthetic note"
        let panel = NSPanel(contentRect: CGRect(x: -100_000, y: -100_000, width: 436, height: 400),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let host = NSHostingView(rootView: ContextNoteDetailView(
            draft: draft, canSetReminder: saved, onCopy: {}, onNavigate: {}, onSave: {}, onClose: {},
            onCopyScreenshot: { _ in }, onOpenScreenshot: { _ in }
        ).environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .frame(width: 436, height: 400))
        host.sizingOptions = []
        panel.contentView = host
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(panel.frame) })
        panel.orderFrontRegardless()
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        var pickers: [NSObject] = []
        func visit(_ object: NSObject) {
            func value(_ key: String) -> Any? {
                object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
            }
            if value("accessibilityRole") as? String == NSAccessibility.Role.popUpButton.rawValue { pickers.append(object) }
            for child in value("accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
        }
        visit(host)
        #expect(pickers.count == (saved ? 1 : 0))
        if saved {
            let picker = try #require(pickers.first)
            let label = picker.value(forKey: "accessibilityLabel") as? String
            let value = picker.value(forKey: "accessibilityValue") as? String
            #expect(label == AppLocalization.string("主动提醒", locale: language.locale))
            #expect(value == AppLocalization.string("不主动提醒", locale: language.locale))
        }
        #expect(draft.reminderInterval == .off)
        #expect(draft.text == "Synthetic note")
    }
}
