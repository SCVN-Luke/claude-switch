import Foundation
import Testing
@testable import ClaudeSwitchCore

struct L10nTests {
    @Test func everyKeyHasEveryLanguage() {
        for key in L10nKey.allCases {
            for lang in AppLanguage.allCases {
                let s = L10n.table[key]?[lang]
                #expect(s != nil && !s!.isEmpty, "missing \(lang.rawValue) for \(key.rawValue)")
            }
        }
    }

    @Test func placeholdersMatchAcrossLanguages() {
        let pattern = try! NSRegularExpression(pattern: #"\{[a-z]+\}"#)
        func placeholders(_ s: String) -> Set<String> {
            Set(pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) })
        }
        for key in L10nKey.allCases {
            let english = placeholders(L10n.t(key, .en))
            for lang in AppLanguage.allCases {
                #expect(placeholders(L10n.table[key]?[lang] ?? "") == english, "\(key.rawValue) \(lang.rawValue)")
            }
        }
    }

    @Test func substitutesArguments() {
        #expect(L10n.t(.confirmSwitchTitle, .en, ["name": "Work"]) == "Switch to “Work”?")
        #expect(L10n.t(.confirmSwitchTitle, .vi, ["name": "Work"]) == "Chuyển sang “Work”?")
    }

    @Test func preferredLanguageFromSystem() {
        #expect(AppLanguage.preferred(from: ["vi-VN", "en-US"]) == .vi)
        #expect(AppLanguage.preferred(from: ["ko-KR"]) == .ko)
        #expect(AppLanguage.preferred(from: ["fr-FR", "ko"]) == .ko)
        #expect(AppLanguage.preferred(from: ["fr-FR"]) == .en)
        #expect(AppLanguage.preferred(from: []) == .en)
    }

    @Test func displayNamesAreNative() {
        #expect(AppLanguage.en.displayName == "English")
        #expect(AppLanguage.vi.displayName == "Tiếng Việt")
        #expect(AppLanguage.ko.displayName == "한국어")
    }

    @Test func languageAndGuideFlagPersist() throws {
        let root = makeTempDir()
        let store = ProfileStore(root: root)
        #expect(try store.load().language == nil)
        #expect(try store.load().guideShown != true)
        try store.setLanguage(.ko)
        try store.markGuideShown()
        let reloaded = try ProfileStore(root: root).load()
        #expect(reloaded.language == .ko)
        #expect(reloaded.guideShown == true)
    }

    @Test func oldProfilesFileWithoutNewKeysStillLoads() throws {
        let root = makeTempDir()
        try Data(#"{"profiles":[{"id":"488D0800-31A8-43AD-B684-C107DBAC0F0F","name":"Account 1"}]}"#.utf8)
            .write(to: root.appendingPathComponent("profiles.json"))
        let file = try ProfileStore(root: root).load()
        #expect(file.profiles.count == 1)
        #expect(file.language == nil)
    }
}
