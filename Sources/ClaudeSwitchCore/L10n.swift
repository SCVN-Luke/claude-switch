import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case en, vi, ko

    public var id: String { rawValue }

    /// Shown in the language picker, always in the language itself.
    public var displayName: String {
        switch self {
        case .en: return "English"
        case .vi: return "Tiếng Việt"
        case .ko: return "한국어"
        }
    }

    /// First supported language in the system's preference list; English otherwise.
    public static func preferred(from systemLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        for code in systemLanguages {
            let base = code.split(separator: "-").first.map(String.init) ?? code
            if let lang = AppLanguage(rawValue: base) { return lang }
        }
        return .en
    }
}

public enum L10nKey: String, CaseIterable, Sendable {
    // Menu
    case refreshUsage, switchButton, switchCarry, manageProfiles, guide, quit, language, keychainHint
    // Usage line
    case usageWeek, usageReset, usageStale, notSignedIn
    // Manage window
    case tabSessions, tabProfiles, sessionsOf, searchPlaceholder, showArchived, toProfile, choose,
         selectedCount, switchAndCarry, untitled, newProfileName, add, loginHint, defaultProfile, openToLogin
    // Alerts
    case cancel, confirmSwitchTitle, confirmSwitchText, forceQuitTitle, forceQuitText, forceQuitButton,
         switchFailed, claudeMissing, openApplications, busy, launchFailed, transferNotSignedIn,
         transferIssuesTitle, alreadyThere, openNowTitle, openNowText, openNowButton, removeTitle, removeText,
         removeListOnly, removeWithData, cannotDeleteTitle, cannotDeleteText, removeFailed, createFailed, loadFailed
    // Guide
    case guideTitle, previous, next, stepOf, keychainDialogText
    case step1Title, step1Body, step2Title, step2Body, step3Title, step3Body, step4Title, step4Body,
         step5Title, step5Body, step6Title, step6Body, step7Title, step7Body, step8Title, step8Body,
         step9Title, step9Body
}

public enum L10n {
    /// `{name}`-style placeholders are replaced from `args`.
    public static func t(_ key: L10nKey, _ lang: AppLanguage, _ args: [String: String] = [:]) -> String {
        var s = table[key]?[lang] ?? table[key]?[.en] ?? key.rawValue
        for (k, v) in args { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }

    private static func e(_ en: String, _ vi: String, _ ko: String) -> [AppLanguage: String] {
        [.en: en, .vi: vi, .ko: ko]
    }

    static let table: [L10nKey: [AppLanguage: String]] = [
        // MARK: Menu
        .refreshUsage: e("Refresh usage", "Làm mới usage", "사용량 새로고침"),
        .switchButton: e("Switch", "Switch", "전환"),
        .switchCarry: e("Switch & carry sessions…", "Switch & mang phiên…", "전환 및 세션 가져가기…"),
        .manageProfiles: e("Manage profiles…", "Quản lý profile…", "프로필 관리…"),
        .guide: e("Guide…", "Hướng dẫn…", "사용 가이드…"),
        .quit: e("Quit", "Thoát", "종료"),
        .language: e("Language", "Ngôn ngữ", "언어"),
        .keychainHint: e(
            "No Keychain access to “Claude Safe Storage”, so usage may be stale. Reopen the app and choose Always Allow.",
            "Chưa có quyền Keychain “Claude Safe Storage” nên usage có thể cũ. Mở lại app và chọn Always Allow.",
            "키체인 “Claude Safe Storage” 접근 권한이 없어 사용량이 오래된 값일 수 있습니다. 앱을 다시 열고 ‘항상 허용’을 선택하세요."),

        // MARK: Usage line
        .usageWeek: e("Week", "Tuần", "주간"),
        .usageReset: e("reset", "reset", "초기화"),
        .usageStale: e("stale", "cũ", "오래됨"),
        .notSignedIn: e("not signed in", "chưa đăng nhập", "로그인 안 됨"),

        // MARK: Manage window
        .tabSessions: e("Carry sessions", "Mang phiên", "세션 가져가기"),
        .tabProfiles: e("Profiles", "Profile", "프로필"),
        .sessionsOf: e("Sessions of “{name}”", "Phiên của “{name}”", "“{name}”의 세션"),
        .searchPlaceholder: e("Search by title or folder", "Tìm theo tên hoặc thư mục", "제목 또는 폴더로 검색"),
        .showArchived: e("Show archived sessions", "Hiện phiên đã archive", "보관된 세션 표시"),
        .toProfile: e("To profile", "Sang profile", "대상 프로필"),
        .choose: e("Choose…", "Chọn…", "선택…"),
        .selectedCount: e("{count} selected", "{count} phiên được chọn", "{count}개 선택됨"),
        .switchAndCarry: e("Switch & carry", "Switch & mang theo", "전환 및 가져가기"),
        .untitled: e("(untitled)", "(không tên)", "(제목 없음)"),
        .newProfileName: e("New profile name", "Tên profile mới", "새 프로필 이름"),
        .add: e("Add", "Thêm", "추가"),
        .loginHint: e(
            "A new profile needs one sign-in: click “Open to sign in” and sign in to the account in Claude.",
            "Profile mới cần đăng nhập một lần: bấm “Mở để đăng nhập”, đăng nhập account trong Claude.",
            "새 프로필은 한 번 로그인해야 합니다. “로그인하러 열기”를 클릭하고 Claude에서 계정에 로그인하세요."),
        .defaultProfile: e("Default", "Mặc định", "기본"),
        .openToLogin: e("Open to sign in", "Mở để đăng nhập", "로그인하러 열기"),

        // MARK: Alerts
        .cancel: e("Cancel", "Huỷ", "취소"),
        .confirmSwitchTitle: e("Switch to “{name}”?", "Chuyển sang “{name}”?", "“{name}”(으)로 전환할까요?"),
        .confirmSwitchText: e(
            "Claude will quit, and running sessions will stop.",
            "Claude sẽ được tắt, các phiên đang chạy sẽ dừng.",
            "Claude가 종료되고 실행 중인 세션이 중지됩니다."),
        .forceQuitTitle: e("Claude hasn't quit. Force quit?", "Claude chưa tắt. Buộc tắt?", "Claude가 종료되지 않았습니다. 강제 종료할까요?"),
        .forceQuitText: e("Claude did not exit within 10 seconds.", "Claude không tự thoát sau 10 giây.", "Claude가 10초 안에 종료되지 않았습니다."),
        .forceQuitButton: e("Force quit", "Buộc tắt", "강제 종료"),
        .switchFailed: e("Switch failed", "Switch thất bại", "전환 실패"),
        .claudeMissing: e(
            "Claude.app was not found in the Applications folder.",
            "Không tìm thấy Claude.app trong thư mục Applications.",
            "응용 프로그램 폴더에서 Claude.app을 찾을 수 없습니다."),
        .openApplications: e("Open Applications", "Mở Applications", "응용 프로그램 열기"),
        .busy: e("A switch is already in progress.", "Đang switch, vui lòng đợi.", "이미 전환 중입니다."),
        .launchFailed: e("Couldn't open Claude: {error}", "Không mở được Claude: {error}", "Claude를 열 수 없습니다: {error}"),
        .transferNotSignedIn: e(
            "sign in to this profile once first",
            "hãy mở profile này và đăng nhập một lần trước",
            "먼저 이 프로필에 한 번 로그인하세요"),
        .transferIssuesTitle: e(
            "Some sessions were not carried over",
            "Một số phiên chưa được mang qua",
            "일부 세션을 가져가지 못했습니다"),
        .alreadyThere: e("already there", "đã có", "이미 있음"),
        .openNowTitle: e("Open it to sign in now?", "Mở để đăng nhập ngay?", "지금 열어서 로그인할까요?"),
        .openNowText: e(
            "Claude will open with profile “{name}” so you can sign in to the account.",
            "Claude sẽ mở với profile “{name}” để bạn đăng nhập account.",
            "계정에 로그인할 수 있도록 “{name}” 프로필로 Claude가 열립니다."),
        .openNowButton: e("Open now", "Mở ngay", "지금 열기"),
        .removeTitle: e("Remove profile “{name}”?", "Xoá profile “{name}”?", "“{name}” 프로필을 삭제할까요?"),
        .removeText: e(
            "Also delete this profile's sign-in data?",
            "Có xoá luôn dữ liệu đăng nhập của profile này không?",
            "이 프로필의 로그인 데이터도 삭제할까요?"),
        .removeListOnly: e("Remove from list only", "Chỉ xoá khỏi danh sách", "목록에서만 삭제"),
        .removeWithData: e("Delete data too", "Xoá cả dữ liệu", "데이터도 삭제"),
        .cannotDeleteTitle: e("Couldn't delete the data", "Không xoá được dữ liệu", "데이터를 삭제할 수 없습니다"),
        .cannotDeleteText: e(
            "Claude is running on this profile. Switch to another profile first.",
            "Claude đang chạy với profile này. Hãy switch sang profile khác trước.",
            "Claude가 이 프로필로 실행 중입니다. 먼저 다른 프로필로 전환하세요."),
        .removeFailed: e("Couldn't remove the profile", "Không xoá được profile", "프로필을 삭제할 수 없습니다"),
        .createFailed: e("Couldn't create the profile", "Không tạo được profile", "프로필을 만들 수 없습니다"),
        .loadFailed: e("Couldn't read the profile list", "Không đọc được danh sách profile", "프로필 목록을 읽을 수 없습니다"),

        // MARK: Guide
        .guideTitle: e("Claude Switch Guide", "Hướng dẫn Claude Switch", "Claude Switch 사용 가이드"),
        .previous: e("Previous", "Trước", "이전"),
        .next: e("Next", "Tiếp", "다음"),
        .stepOf: e("Step {n} of {total}", "Bước {n} / {total}", "{total}단계 중 {n}단계"),
        .keychainDialogText: e(
            "ClaudeSwitch wants to use your confidential information stored in “Claude Safe Storage” in your keychain.",
            "ClaudeSwitch muốn dùng thông tin bảo mật lưu trong “Claude Safe Storage” của keychain.",
            "ClaudeSwitch에서 키체인의 “Claude Safe Storage”에 저장된 기밀 정보를 사용하려고 합니다."),

        .step1Title: e("Open the menu", "Mở menu", "메뉴 열기"),
        .step1Body: e(
            "Click the Claude Switch icon (two people) in the menu bar. Each row is a profile: ✓ marks the one Claude is running now, and the numbers are its current usage — the 5-hour limit with its reset time, and the weekly limit.",
            "Bấm icon Claude Switch (hình hai người) trên thanh menu. Mỗi dòng là một profile: dấu ✓ là profile Claude đang chạy, các con số là usage hiện tại — giới hạn 5 giờ kèm giờ reset, và giới hạn tuần.",
            "메뉴 막대에서 Claude Switch 아이콘(두 사람 모양)을 클릭하세요. 각 행은 하나의 프로필입니다. ✓ 표시는 지금 Claude가 실행 중인 프로필이고, 숫자는 현재 사용량(초기화 시각이 표시된 5시간 한도와 주간 한도)입니다."),
        .step2Title: e("Open “Manage profiles”", "Mở “Quản lý profile”", "“프로필 관리” 열기"),
        .step2Body: e(
            "At first there is only Account 1 — the account Claude is signed in to today. Click “Manage profiles…” at the bottom of the menu to add your second account.",
            "Lúc đầu chỉ có Account 1 — account Claude đang đăng nhập. Bấm “Quản lý profile…” ở cuối menu để thêm account thứ hai.",
            "처음에는 지금 Claude에 로그인된 Account 1만 있습니다. 두 번째 계정을 추가하려면 메뉴 아래쪽의 “프로필 관리…”를 클릭하세요."),
        .step3Title: e("Add Account 2", "Thêm Account 2", "Account 2 추가"),
        .step3Body: e(
            "On the Profiles tab, type a name for the second account (for example “Account 2”) and click Add. Claude Switch creates a separate, empty data folder for it.",
            "Ở tab Profile, gõ tên cho account thứ hai (ví dụ “Account 2”) rồi bấm Thêm. Claude Switch tạo một thư mục dữ liệu riêng, trống cho nó.",
            "프로필 탭에서 두 번째 계정의 이름(예: “Account 2”)을 입력하고 추가를 클릭하세요. Claude Switch가 이 계정 전용의 빈 데이터 폴더를 만듭니다."),
        .step4Title: e("Open it to sign in", "Mở để đăng nhập", "로그인하러 열기"),
        .step4Body: e(
            "Choose “Open now”. Claude Switch asks before quitting Claude (running sessions stop), then opens Claude on the new profile.",
            "Chọn “Mở ngay”. Claude Switch sẽ hỏi trước khi tắt Claude (các phiên đang chạy sẽ dừng), rồi mở Claude với profile mới.",
            "“지금 열기”를 선택하세요. Claude Switch는 Claude를 종료하기 전에 확인을 요청하고(실행 중인 세션은 중지됨), 새 프로필로 Claude를 엽니다."),
        .step5Title: e("Sign in to Account 2", "Đăng nhập Account 2", "Account 2에 로그인"),
        .step5Body: e(
            "Claude opens like a fresh install. Sign in with your second account. You only do this once — the sign-in is remembered in that profile, and Account 1 stays signed in to its own.",
            "Claude mở ra như mới cài. Đăng nhập bằng account thứ hai. Chỉ cần làm một lần — đăng nhập được lưu trong profile đó, Account 1 vẫn giữ đăng nhập của nó.",
            "Claude가 새로 설치한 것처럼 열립니다. 두 번째 계정으로 로그인하세요. 한 번만 하면 됩니다. 로그인 정보는 해당 프로필에 저장되고, Account 1은 자신의 로그인을 그대로 유지합니다."),
        .step6Title: e("Allow Keychain access", "Cho phép truy cập Keychain", "키체인 접근 허용"),
        .step6Body: e(
            "The first time Claude Switch reads usage, macOS asks whether it may use “Claude Safe Storage”. Choose Always Allow. Without it you only see older usage figures, marked “stale”.",
            "Lần đầu Claude Switch đọc usage, macOS hỏi có cho dùng “Claude Safe Storage” không. Chọn Always Allow. Nếu không, bạn chỉ thấy số usage cũ, có nhãn “cũ”.",
            "Claude Switch가 처음 사용량을 읽을 때 macOS가 “Claude Safe Storage” 사용 허용 여부를 묻습니다. ‘항상 허용’을 선택하세요. 허용하지 않으면 “오래됨” 표시가 붙은 이전 사용량만 보입니다."),
        .step7Title: e("Switch accounts", "Đổi account", "계정 전환"),
        .step7Body: e(
            "Open the menu, click the profile you want, then click Switch. Claude quits and reopens signed in to that account — no logging out and back in.",
            "Mở menu, bấm vào profile muốn dùng, rồi bấm Switch. Claude tắt và mở lại với account đó — không cần logout rồi login lại.",
            "메뉴를 열고 원하는 프로필을 클릭한 다음 전환을 클릭하세요. Claude가 종료된 후 해당 계정으로 로그인된 상태로 다시 열립니다. 로그아웃 후 다시 로그인할 필요가 없습니다."),
        .step8Title: e("Carry sessions over", "Mang phiên sang", "세션 가져가기"),
        .step8Body: e(
            "To keep working on Claude Code sessions in the other account, click “Switch & carry sessions…”, tick the sessions, choose the target profile and click “Switch & carry”.",
            "Để làm tiếp các phiên Claude Code ở account kia, bấm “Switch & mang phiên…”, tick các phiên, chọn profile đích rồi bấm “Switch & mang theo”.",
            "다른 계정에서 Claude Code 세션을 계속하려면 “전환 및 세션 가져가기…”를 클릭하고, 세션을 체크한 뒤 대상 프로필을 선택하고 “전환 및 가져가기”를 클릭하세요."),
        .step9Title: e("Your chats are safe", "Hội thoại không bị mất", "대화는 안전합니다"),
        .step9Body: e(
            "Conversation history lives in ~/.claude and is shared by every profile, so switching back and forth never loses messages and you never need to carry a session back. The original stays in the old profile's sidebar; archive it if it gets confusing.",
            "Lịch sử hội thoại nằm ở ~/.claude và dùng chung cho mọi profile, nên chuyển qua lại không mất tin nhắn và không cần mang phiên ngược lại. Bản gốc vẫn còn trên sidebar profile cũ; có thể archive nếu thấy rối.",
            "대화 기록은 ~/.claude에 저장되며 모든 프로필이 공유합니다. 따라서 여러 번 전환해도 메시지가 사라지지 않고, 세션을 다시 가져올 필요도 없습니다. 원본 세션은 이전 프로필의 사이드바에 남아 있으니 헷갈리면 보관하세요."),
    ]
}
