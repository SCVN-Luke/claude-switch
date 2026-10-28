import ClaudeSwitchCore
import SwiftUI

struct GuideStep: Identifiable {
    enum Illustration { case menuBar, manageProfiles, addProfile, openNow, signIn, keychain, switchProfile, carry, chatsSafe }

    let id: Int
    let title: L10nKey
    let body: L10nKey
    let illustration: Illustration

    static let all: [GuideStep] = [
        GuideStep(id: 1, title: .step1Title, body: .step1Body, illustration: .menuBar),
        GuideStep(id: 2, title: .step2Title, body: .step2Body, illustration: .manageProfiles),
        GuideStep(id: 3, title: .step3Title, body: .step3Body, illustration: .addProfile),
        GuideStep(id: 4, title: .step4Title, body: .step4Body, illustration: .openNow),
        GuideStep(id: 5, title: .step5Title, body: .step5Body, illustration: .signIn),
        GuideStep(id: 6, title: .step6Title, body: .step6Body, illustration: .keychain),
        GuideStep(id: 7, title: .step7Title, body: .step7Body, illustration: .switchProfile),
        GuideStep(id: 8, title: .step8Title, body: .step8Body, illustration: .carry),
        GuideStep(id: 9, title: .step9Title, body: .step9Body, illustration: .chatsSafe),
    ]
}

/// Read-only, step-by-step guide. Nothing in it changes profiles or touches Claude.
struct GuideView: View {
    @EnvironmentObject var model: AppModel
    @State private var current = 1

    var body: some View {
        HStack(spacing: 0) {
            List(GuideStep.all, selection: Binding(get: { current }, set: { current = $0 ?? current })) { step in
                Text("\(step.id). \(model.t(step.title))").tag(step.id)
            }
            .listStyle(.sidebar)
            .frame(width: 230)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    LanguagePicker()
                }
                .padding([.top, .horizontal], 12)
                ScrollView {
                    GuideStepPage(step: GuideStep.all[current - 1], language: model.language)
                        .padding(20)
                }
                Divider()
                HStack {
                    Button(model.t(.previous)) { current -= 1 }.disabled(current == 1)
                    Spacer()
                    Text(model.t(.stepOf, ["n": "\(current)", "total": "\(GuideStep.all.count)"]))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.t(.next)) { current += 1 }
                        .keyboardShortcut(.defaultAction)
                        .disabled(current == GuideStep.all.count)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

/// Title, text and illustration of one step. Also rendered to PNG by `GuideExporter`.
struct GuideStepPage: View {
    let step: GuideStep
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(step.id). \(L10n.t(step.title, language))").font(.title2.bold())
            Text(L10n.t(step.body, language))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            GuideIllustration(kind: step.illustration, language: language)
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor)))
        }
        .frame(width: 640, alignment: .leading)
    }
}

struct GuideIllustration: View {
    let kind: GuideStep.Illustration
    let language: AppLanguage

    var body: some View {
        content
            .environment(\.locale, Locale(identifier: language.rawValue))
            .allowsHitTesting(false)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .menuBar:
            let m = SampleData.model(profiles: 1, language: language)
            VStack(alignment: .trailing, spacing: 6) {
                FakeMenuBar()
                MenuView().environmentObject(m).panel()
            }
            .guideHighlight([.menuBarIcon])
        case .manageProfiles:
            MenuView().environmentObject(SampleData.model(profiles: 1, language: language)).panel()
                .guideHighlight([.manageProfiles])
        case .addProfile:
            ProfilesTab(newName: "Account 2").environmentObject(SampleData.model(profiles: 1, language: language))
                .frame(width: 560, height: 230).padding(14).panel()
                .guideHighlight([.addProfile])
        case .openNow:
            MockAlert(title: L10n.t(.openNowTitle, language),
                      text: L10n.t(.openNowText, language, ["name": "Account 2"]),
                      buttons: [L10n.t(.openNowButton, language), L10n.t(.cancel, language)])
                .guideHighlight([.alertPrimary])
        case .signIn:
            IconCard(symbol: "person.crop.circle.badge.checkmark", caption: "claude.ai")
        case .keychain:
            // macOS draws this dialog itself, in the system language; its buttons are shown in English.
            MockAlert(title: "ClaudeSwitch", text: L10n.t(.keychainDialogText, language),
                      buttons: ["Always Allow", "Deny", "Allow"], symbol: "lock.fill")
                .guideHighlight([.alertPrimary])
        case .switchProfile:
            MenuView().environmentObject(SampleData.model(profiles: 2, language: language)).panel()
                .guideHighlight([.profileRow2, .switchButton])
        case .carry:
            SessionsTab(checked: SampleData.checkedSessions)
                .environmentObject(SampleData.model(profiles: 2, language: language))
                .frame(width: 560, height: 300).padding(14).panel()
                .guideHighlight([.switchAndCarry])
        case .chatsSafe:
            IconCard(symbol: "bubble.left.and.bubble.right.fill", caption: "~/.claude/projects")
        }
    }
}

// MARK: - Pieces used only by the Guide

private extension View {
    func panel() -> some View {
        background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

private struct FakeMenuBar: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "person.2.circle").font(.system(size: 15)).guideTarget(.menuBarIcon)
            Text("13:05")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
    }
}

private struct MockAlert: View {
    let title: String
    let text: String
    let buttons: [String]
    var symbol = "person.2.circle"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.tint)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(text).font(.callout).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(buttons.enumerated()), id: \.offset) { i, label in
                Text(label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(i == 0 ? Color.accentColor : Color.secondary.opacity(0.2)))
                    .foregroundStyle(i == 0 ? Color.white : Color.primary)
                    .modifier(PrimaryTag(isPrimary: i == 0))
            }
        }
        .padding(18)
        .frame(width: 280)
        .panel()
    }
}

private struct PrimaryTag: ViewModifier {
    let isPrimary: Bool
    func body(content: Content) -> some View {
        if isPrimary { content.guideTarget(.alertPrimary) } else { content }
    }
}

private struct IconCard: View {
    let symbol: String
    let caption: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 56)).foregroundStyle(.tint)
            Text(caption).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

/// Sample state for the illustrations; never written anywhere.
@MainActor
enum SampleData {
    static let account1 = Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Account 1", dataDir: nil)
    static let account2 = Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Account 2",
                                  dataDir: "~/Library/Application Support/ClaudeSwitch/Profiles/A2")
    static let checkedSessions: Set<String> = ["s1", "s2"]

    static func model(profiles count: Int, language: AppLanguage) -> AppModel {
        let m = AppModel(preview: true)
        m.setLanguage(language)
        m.profiles = count == 1 ? [account1] : [account1, account2]
        m.running = account1
        m.selected = count == 1 ? nil : account2.id
        m.transferTarget = account2.id
        let now = Date()
        m.usage[account1.id] = .usage(UsageSnapshot(fiveHourPct: 48, fiveHourResetsAt: now.addingTimeInterval(2 * 3600),
                                                    weeklyPct: 33, fetchedAt: now, source: .live))
        m.usage[account2.id] = .usage(UsageSnapshot(fiveHourPct: 12, fiveHourResetsAt: now.addingTimeInterval(4 * 3600),
                                                    weeklyPct: 20, fetchedAt: now, source: .live))
        let home = "/Users/you/Projects"
        m.sessions = [
            SessionInfo(id: "s1", title: "Refactor login flow", cwd: "\(home)/web-app",
                        lastActivityAt: now.addingTimeInterval(-600), isArchived: false, fileURL: URL(fileURLWithPath: "/dev/null")),
            SessionInfo(id: "s2", title: "Fix shader banding", cwd: "\(home)/game",
                        lastActivityAt: now.addingTimeInterval(-7200), isArchived: false, fileURL: URL(fileURLWithPath: "/dev/null")),
            SessionInfo(id: "s3", title: "Write release notes", cwd: "\(home)/docs",
                        lastActivityAt: now.addingTimeInterval(-86400 * 2), isArchived: false, fileURL: URL(fileURLWithPath: "/dev/null")),
        ]
        return m
    }
}
