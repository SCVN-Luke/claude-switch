# ClaudeSwitch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menu bar app macOS chuyển Claude Desktop giữa nhiều profile (`--user-data-dir`), mang phiên Code sang profile mới và hiện usage live của từng profile.

**Architecture:** Swift package gồm library `ClaudeSwitchCore` (toàn bộ logic, chỉ nhận đường dẫn/dependency qua init để test bằng thư mục giả) và executable `ClaudeSwitch` (SwiftUI `MenuBarExtra` + một `Window`). `scripts/build-app.sh` đóng gói binary thành `ClaudeSwitch.app` (`LSUIElement`, ký ad-hoc).

**Tech Stack:** Swift 6.3 (Command Line Tools, không có Xcode), SwiftPM, SwiftUI/AppKit, Swift Testing (`import Testing`), SQLite3, CommonCrypto, CryptoKit, Security. Không dependency ngoài.

**Spec:** `docs/superpowers/specs/2026-10-28-claude-switch-design.md`

## Global Constraints

- macOS 14+ (`platforms: [.macOS(.v14)]`), swift-tools-version 6.0.
- Không thêm package ngoài; chỉ framework hệ thống.
- Không bao giờ ghi/log/hiện `sessionKey`, mật khẩu Keychain hay các key `oauth:*`.
- Không bao giờ sửa/xoá dữ liệu trong data dir nguồn; chỉ ghi vào `claude-code-sessions/<acc>/<org>/` của đích và vào thư mục của ClaudeSwitch.
- Thư mục app: `~/Library/Application Support/ClaudeSwitch/` (`profiles.json`, `Profiles/<id>/`). Log: `~/Library/Logs/ClaudeSwitch.log`.
- Data dir mặc định của Claude: `~/Library/Application Support/Claude` ↔ profile có `dataDir == nil`.
- Bundle id Claude: `com.anthropic.claudefordesktop` (hằng ở Task 6; fallback đường dẫn `/Applications/Claude.app`).
- UI tiếng Việt, đúng các nhãn trong spec §5.
- Usage API: `GET https://claude.ai/api/organizations/{org}/usage`, header `Cookie: sessionKey=…`, `Accept: application/json`, UA kiểu Electron như `scripts/spike-usage.swift`, timeout 15s.
- Làm mới usage: khi mở menu nếu dữ liệu > 60s; nền mỗi 300s.
- Ngưỡng màu: < 70 thường, 70–90 vàng, > 90 đỏ.

## Review Focus

1. Claude Desktop đang chạy khi đọc `Cookies` / `local_*.json` → phải đọc từ bản copy tạm, không lỗi "database is locked" (Task 4 test copy-then-read).
2. Profile mới chưa đăng nhập (data dir rỗng hoặc chỉ có vài file) → menu hiện "chưa đăng nhập", không crash, không gọi API (Task 3, Task 5 tests).
3. Phiên đã tồn tại ở đích / đích chưa có thư mục org → bỏ qua đúng phiên đó hoặc tạo thư mục; các phiên còn lại vẫn copy (Task 3 test).
4. Đường dẫn data dir có dấu cách (`Application Support`) trong `--user-data-dir=` và trong so khớp process args → so khớp sau `standardizedFileURL` (Task 6 test).
5. API trả 401/403/HTML Cloudflare hoặc JSON thiếu `five_hour` → fallback snapshot file, `source == .file` (Task 5 test).

---

## File Structure

```
Package.swift
Sources/ClaudeSwitchCore/
  Paths.swift            — các URL mặc định (app support, Claude default data dir, log)
  Log.swift              — ghi log ra file + os_log
  Profile.swift          — Profile, ProfilesFile, ProfileStore
  ClaudeDataDir.swift    — đọc account/org/sessions/snapshot usage
  SessionTransfer.swift  — copy phiên giữa hai data dir
  CookieReader.swift     — đọc + giải mã cookie claude.ai
  Usage.swift            — UsageSnapshot, UsageClient, UsageService
  ClaudeLauncher.swift   — quit/launch/nhận diện profile đang chạy
  SwitchCoordinator.swift— luồng Switch (quit → transfer → launch)
Sources/ClaudeSwitch/
  ClaudeSwitchApp.swift  — @main, MenuBarExtra + Window
  AppModel.swift         — @MainActor ObservableObject nối Core với UI
  MenuView.swift
  ManageWindow.swift     — tab Mang phiên + tab Profile
Tests/ClaudeSwitchCoreTests/
  Fixtures.swift         — tạo data dir giả trong temp
  ProfileStoreTests.swift, ClaudeDataDirTests.swift, SessionTransferTests.swift,
  CookieReaderTests.swift, UsageTests.swift, ClaudeLauncherTests.swift, SwitchCoordinatorTests.swift
scripts/build-app.sh, scripts/Info.plist
```

---

### Task 1: Package skeleton + ProfileStore

**Files:**
- Create: `Package.swift`, `.gitignore` (`.build/`, `build/`), `Sources/ClaudeSwitchCore/Paths.swift`, `Sources/ClaudeSwitchCore/Log.swift`, `Sources/ClaudeSwitchCore/Profile.swift`, `Sources/ClaudeSwitch/ClaudeSwitchApp.swift` (tạm: `@main struct` với `MenuBarExtra("Claude Switch", systemImage: "person.2.circle") { Text("…") }`)
- Test: `Tests/ClaudeSwitchCoreTests/Fixtures.swift`, `Tests/ClaudeSwitchCoreTests/ProfileStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum Paths { static var appSupport: URL; static var claudeDefaultDataDir: URL; static var logFile: URL }`
  - `enum Log { static func info(_ s: String); static func error(_ s: String) }` (ghi file + `os_log`)
  - `struct Profile: Codable, Identifiable, Equatable { var id: UUID; var name: String; var dataDir: String? }` + `func resolvedDataDir(defaultDir: URL) -> URL`
  - `struct ProfilesFile: Codable { var profiles: [Profile]; var activeProfileId: UUID? }`
  - `final class ProfileStore { init(root: URL); func load() throws -> ProfilesFile; func save(_: ProfilesFile) throws; func addProfile(name: String) throws -> Profile; func rename(id: UUID, to: String) throws; func remove(id: UUID, deleteData: Bool) throws; func setActive(_ id: UUID?) throws }`
  - `enum ProfileError: Error { case cannotRemoveDefault, notFound }`
  - Test helper `func makeTempDir() -> URL`

- [ ] **Step 1:** `git init`, tạo `Package.swift` (library `ClaudeSwitchCore`, executable `ClaudeSwitch` phụ thuộc Core, testTarget), `.gitignore`. Chạy `swift build` → thành công.
- [ ] **Step 2: Viết test fail** trong `ProfileStoreTests.swift`:
  - `firstLoadCreatesDefaultProfile`: `load()` trên root rỗng → đúng 1 profile, `name == "Account 1"`, `dataDir == nil`, và `profiles.json` tồn tại.
  - `addProfileCreatesDataDir`: `addProfile(name: "Account 2")` → `dataDir == root/Profiles/<id>` và thư mục tồn tại; load lại thấy 2 profile.
  - `removeDefaultThrows`: `remove(id: default.id, deleteData: false)` ném `ProfileError.cannotRemoveDefault`.
  - `removeKeepsDataByDefault`: remove với `deleteData: false` → thư mục vẫn còn; `true` → bị xoá.
  - `renamePersists`, `setActivePersists`.
- [ ] **Step 3:** `swift test --filter ProfileStoreTests` → FAIL (chưa có type). Nếu `import Testing` không có trên CLT → dừng và báo lại (không chuyển sang XCTest khi chưa hỏi).
- [ ] **Step 4:** Implement `Paths`, `Log`, `Profile`, `ProfileStore`. `save` ghi atomically (`Data.write(options: .atomic)`), JSON `prettyPrinted, sortedKeys`.
- [ ] **Step 5:** `swift test --filter ProfileStoreTests` → PASS.
- [ ] **Step 6:** Commit `feat: package skeleton and ProfileStore`.

### Task 2: ClaudeDataDir (account, org, sessions, snapshot usage)

**Files:**
- Create: `Sources/ClaudeSwitchCore/ClaudeDataDir.swift`
- Modify: `Tests/ClaudeSwitchCoreTests/Fixtures.swift` (thêm builder data dir giả)
- Test: `Tests/ClaudeSwitchCoreTests/ClaudeDataDirTests.swift`

**Interfaces:**
- Consumes: `makeTempDir()`.
- Produces:
  - `struct SessionInfo: Identifiable, Equatable { var id: String /* sessionId */; var title: String; var cwd: String; var lastActivityAt: Date?; var isArchived: Bool; var fileURL: URL }`
  - `struct UsageSnapshot: Equatable { enum Source { case live, file }; var fiveHourPct: Double?; var fiveHourResetsAt: Date?; var weeklyPct: Double?; var weeklyResetsAt: Date?; var extraPct: Double?; var fetchedAt: Date; var source: Source }` (đặt trong file này vì snapshot file trả về nó)
  - `struct ClaudeDataDir { let url: URL; init(url: URL); var accountUuid: String? { get }; func orgUuid(cookieOrg: String?) -> String?; func sessions() -> [SessionInfo]; func snapshotUsage(org: String?) -> UsageSnapshot?; var sessionsDir: URL? /* claude-code-sessions/<acc>/<org> khi xác định được */ }`
  - Fixture: `struct FakeDataDir { static func make(account: String?, orgs: [String], sessions: [String: [[String: Any]]] /* org → json */, usageSamples: [[String: Any]]) -> URL }`

- [ ] **Step 1: Viết test fail:**
  - `accountFromConfig`: `config.json` `{"lastKnownAccountUuid":"acc1"}` → `"acc1"`; không có file → `nil`.
  - `orgPrefersCookie`: `orgUuid(cookieOrg: "orgX")` → `"orgX"`.
  - `orgSingleFolder`: 1 thư mục org → trả về nó; 2 thư mục + sample mới nhất `org:"o2"` → `"o2"`; 2 thư mục, không sample → `nil`.
  - `sessionsParsesAndSkipsBroken`: 2 file `local_a.json` hợp lệ (`sessionId,title,cwd,lastActivityAt(ms),isArchived`) + 1 file rác → trả về 2, sắp theo `lastActivityAt` giảm dần, `lastActivityAt` đổi ms→Date.
  - `snapshotUsageLatestForOrg`: samples `[{t:1000,org:"o1",u:{fh:10,sd:20}}, {t:2000,org:"o1",u:{fh:48,sd:33,xu:26.275}}, {t:3000,org:"o2",u:{fh:99}}]` → với org `o1`: `fiveHourPct 48, weeklyPct 33, extraPct 26.275, fetchedAt == Date(ms 2000), source .file`.
  - `notLoggedInDir`: thư mục rỗng → `accountUuid nil`, `sessions() == []`, `snapshotUsage(org: nil) == nil`.
- [ ] **Step 2:** `swift test --filter ClaudeDataDirTests` → FAIL.
- [ ] **Step 3:** Implement với `JSONSerialization` (parse dễ dãi, bỏ key lạ). `sessions()` đọc mọi `local_*.json` dưới `claude-code-sessions/<acc>/*/`.
- [ ] **Step 4:** Test → PASS.
- [ ] **Step 5:** Commit `feat: ClaudeDataDir reader`.

### Task 3: SessionTransfer

**Files:**
- Create: `Sources/ClaudeSwitchCore/SessionTransfer.swift`
- Test: `Tests/ClaudeSwitchCoreTests/SessionTransferTests.swift`

**Interfaces:**
- Consumes: `ClaudeDataDir`, `SessionInfo`, `FakeDataDir`.
- Produces:
  - `enum TransferOutcome: Equatable { case copied, alreadyExists, failed(String) }`
  - `enum TransferError: Error, Equatable { case targetNotLoggedIn }`
  - `enum SessionTransfer { static func transfer(_ sessions: [SessionInfo], to target: ClaudeDataDir, targetOrg: String?) throws -> [String: TransferOutcome] /* key = sessionId */ }`

- [ ] **Step 1: Viết test fail:**
  - `copiesIntoTargetOrgFolder`: nguồn có phiên `s1`; đích account `acc2`, org `org2` (chưa có thư mục org) → file `claude-code-sessions/acc2/org2/local_s1.json` tồn tại, nội dung byte-identical với nguồn, kết quả `["s1": .copied]`; file nguồn vẫn còn.
  - `skipsExisting`: đích đã có `local_s1.json` (nội dung khác) → `.alreadyExists`, nội dung đích không đổi; `s2` vẫn `.copied`.
  - `targetNotLoggedInThrows`: đích không có account → ném `.targetNotLoggedIn`, không tạo file nào.
- [ ] **Step 2:** `swift test --filter SessionTransferTests` → FAIL.
- [ ] **Step 3:** Implement: `createDirectory(withIntermediateDirectories:)`, ghi bằng `Data.write(.atomic)`; lỗi một phiên → `.failed(localizedDescription)`, tiếp tục.
- [ ] **Step 4:** Test → PASS.
- [ ] **Step 5:** Commit `feat: SessionTransfer`.

### Task 4: CookieReader

**Files:**
- Create: `Sources/ClaudeSwitchCore/CookieReader.swift` (chuyển logic từ `scripts/spike-usage.swift`)
- Test: `Tests/ClaudeSwitchCoreTests/CookieReaderTests.swift`

**Interfaces:**
- Produces:
  - `protocol SafeStoragePasswordProvider { func password() throws -> Data }`; `final class KeychainPasswordProvider: SafeStoragePasswordProvider` (service `Claude Safe Storage`, cache trong bộ nhớ, thread-safe bằng `NSLock`)
  - `enum CookieError: Error, Equatable { case notFound, badFormat, decryptFailed, keychain(OSStatus), dbOpenFailed }`
  - `struct ClaudeCookies { var sessionKey: String; var lastActiveOrg: String? }`
  - `enum CookieCrypto { static func deriveKey(password: Data) -> Data; static func decrypt(_ blob: Data, key: Data, hostKey: String, metaVersion: Int) throws -> String; static func encrypt(_ plain: String, key: Data, hostKey: String, metaVersion: Int) -> Data /* chỉ để test */ }`
  - `struct CookieReader { init(passwords: SafeStoragePasswordProvider); func read(dataDir: URL) throws -> ClaudeCookies }`

- [ ] **Step 1: Viết test fail:**
  - `roundTripV24`: `decrypt(encrypt("sk-ant-abc", key, ".claude.ai", 24), key, ".claude.ai", 24) == "sk-ant-abc"`; với version 23 không có prefix hash cũng round-trip.
  - `hostHashMismatchThrows`: mã hoá với host `.claude.ai`, giải mã với `claude.ai` (v24) → `.decryptFailed`.
  - `missingV10PrefixThrows` → `.badFormat`.
  - `readsFromCopyOfDb`: tạo SQLite `Cookies` giả (bảng `cookies(host_key, name, encrypted_value)`, `meta(key,value)` version 24) với `sessionKey` + `lastActiveOrg`, mở thêm một connection giữ `BEGIN EXCLUSIVE` trên file gốc trong lúc gọi `read` → vẫn trả về đúng giá trị (chứng minh đọc từ bản copy); password provider giả.
  - `noSessionKeyThrowsNotFound`.
- [ ] **Step 2:** `swift test --filter CookieReaderTests` → FAIL.
- [ ] **Step 3:** Implement (thuật toán như spike: PBKDF2-SHA1 `saltysalt` 1003 vòng 16 byte; AES-128-CBC IV 16×`0x20`; bỏ 32 byte SHA-256(host) khi version ≥ 24). Copy `Cookies` + `Cookies-journal` + `Cookies-wal` (nếu có) vào thư mục tạm, xoá sau khi đọc.
- [ ] **Step 4:** Test → PASS.
- [ ] **Step 5:** Commit `feat: CookieReader`.

### Task 5: UsageClient + UsageService

**Files:**
- Create: `Sources/ClaudeSwitchCore/Usage.swift`
- Test: `Tests/ClaudeSwitchCoreTests/UsageTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot`, `ClaudeDataDir`, `CookieReader`, `ClaudeCookies`.
- Produces:
  - `enum UsageError: Error, Equatable { case http(Int), badResponse }`
  - `struct UsageClient { init(session: URLSession = .shared); func fetch(org: String, sessionKey: String) async throws -> UsageSnapshot; static func parse(_ data: Data, now: Date) throws -> UsageSnapshot }`
  - `enum ProfileUsageState: Equatable { case notLoggedIn, usage(UsageSnapshot), unavailable }`
  - `actor UsageService { init(client: UsageClient, cookies: CookieReader, now: @escaping () -> Date = Date.init); func usage(for dataDir: URL, force: Bool) async -> ProfileUsageState }` — cache theo data dir, trả cache nếu `now - fetchedAt < 60s` và `!force`; nếu Keychain bị từ chối (`CookieError.keychain`) thì đặt cờ không gọi API nữa trong phiên chạy.

- [ ] **Step 1: Viết test fail:**
  - `parseRealShape`: JSON có `five_hour {utilization:50, resets_at:"2026-10-28T06:20:00.367407+00:00"}`, `seven_day {utilization:39,…}`, `extra_usage {utilization:26.275,…}`, cùng các key lạ (`amber_cistern`, `limits:[]`) → `fiveHourPct 50`, `weeklyPct 39`, `extraPct 26.275`, `fiveHourResetsAt` parse được (ISO8601 có phần lẻ 6 chữ số), `source .live`.
  - `parseMissingFiveHourThrows` → `.badResponse`; `parseNullUtilization` → `fiveHourPct nil` không ném.
  - `fetchSendsCookieAndPath` (URLProtocol giả): request tới `https://claude.ai/api/organizations/o1/usage`, header `Cookie == "sessionKey=k"`, `Accept == "application/json"`.
  - `fetch403Throws` → `.http(403)`; body HTML với 200 → `.badResponse`.
  - `serviceFallsBackToFile`: data dir giả có account + sample `fh:48`, cookie reader giả trả cookie, client trả 403 → `.usage` với `source .file, fiveHourPct 48`.
  - `serviceNotLoggedIn`: data dir rỗng → `.notLoggedIn`, client không được gọi.
  - `serviceCachesFor60s`: 2 lần gọi cách 30s → client gọi 1 lần; cách 61s → 2 lần; `force: true` → luôn gọi.
- [ ] **Step 2:** `swift test --filter UsageTests` → FAIL.
- [ ] **Step 3:** Implement. `CookieReader` cần được trừu tượng hoá để test: thêm `protocol CookieSource { func read(dataDir: URL) throws -> ClaudeCookies }` và cho `CookieReader` conform; `UsageService.init(client:cookies: CookieSource, …)`. Org: `ClaudeDataDir.orgUuid(cookieOrg: cookies.lastActiveOrg)`. Parse ngày bằng `ISO8601DateFormatter` `[.withInternetDateTime, .withFractionalSeconds]`, fallback không phần lẻ.
- [ ] **Step 4:** Test → PASS.
- [ ] **Step 5:** Commit `feat: live usage with file fallback`.

### Task 6: ClaudeLauncher

**Files:**
- Create: `Sources/ClaudeSwitchCore/ClaudeLauncher.swift`
- Test: `Tests/ClaudeSwitchCoreTests/ClaudeLauncherTests.swift`

**Interfaces:**
- Consumes: `Profile`.
- Produces:
  - `enum QuitResult { case notRunning, quit, stillRunning }`
  - `protocol ClaudeControlling { func runningDataDir() -> URL?? /* nil = không chạy; .some(nil) = profile mặc định */; func quit(timeout: TimeInterval) async -> QuitResult; func forceQuit() async; func launch(dataDir: URL?) async throws }`
  - `final class ClaudeLauncher: ClaudeControlling` (bundle id hằng từ Info.plist; `NSWorkspace.openApplication` với `arguments`, `createsNewApplicationInstance = true`; quit = `terminate()` rồi poll `isTerminated` 0,2s đến hết timeout)
  - `enum ProcessArgs { static func arguments(pid: pid_t) -> [String]?; static func userDataDir(from args: [String]) -> URL? }`
  - `func matchProfile(_ runningDir: URL??, in profiles: [Profile], defaultDir: URL) -> Profile?`

- [ ] **Step 1: Viết test fail:**
  - `parseUserDataDirWithSpaces`: `["/App/Claude", "--user-data-dir=/Users/x/Library/Application Support/ClaudeSwitch/Profiles/A"]` → URL đúng đường dẫn có dấu cách; không có flag → `nil`; dạng tách `["--user-data-dir", "/p"]` → `/p`.
  - `argumentsOfSelf`: `ProcessArgs.arguments(pid: getpid())` không nil và phần tử đầu chứa tên test runner (kiểm tra sysctl `KERN_PROCARGS2` chạy được).
  - `matchProfileStandardizes`: running `.some(URL("/a/b/"))` khớp profile `dataDir "/a/b"`; `.some(nil)` → profile mặc định; `nil` → `nil`.
- [ ] **Step 2:** `swift test --filter ClaudeLauncherTests` → FAIL.
- [ ] **Step 3:** Implement. `KERN_PROCARGS2`: buffer bắt đầu bằng `argc` (Int32), rồi exec path, padding `\0`, rồi `argc` chuỗi C. Chọn tiến trình chính: `NSRunningApplication.runningApplications(withBundleIdentifier:)` (helper Electron có bundle id khác).
- [ ] **Step 4:** Test → PASS.
- [ ] **Step 5:** Commit `feat: ClaudeLauncher`.

### Task 7: SwitchCoordinator

**Files:**
- Create: `Sources/ClaudeSwitchCore/SwitchCoordinator.swift`
- Test: `Tests/ClaudeSwitchCoreTests/SwitchCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ClaudeControlling`, `ProfileStore`, `SessionTransfer`, `ClaudeDataDir`, `CookieSource`.
- Produces:
  - `enum SwitchStep: Equatable { case needsForceQuit, done(transfer: [String: TransferOutcome]), failed(String) }`
  - `final class SwitchCoordinator { init(claude: ClaudeControlling, store: ProfileStore, cookies: CookieSource, defaultDir: URL); func switchTo(_ target: Profile, carrying: [SessionInfo], force: Bool) async -> SwitchStep }`

- [ ] **Step 1: Viết test fail** (fake `ClaudeControlling` ghi lại thứ tự lời gọi):
  - `orderQuitTransferLaunch`: Claude đang chạy → thứ tự `quit`, (file phiên xuất hiện ở đích), `launch(target dir)`; `activeProfileId == target.id`; kết quả `.done(["s1": .copied])`.
  - `stillRunningAsksForce`: fake `quit` trả `.stillRunning`, `force: false` → `.needsForceQuit`, không launch, không copy; gọi lại `force: true` → `forceQuit` rồi tiếp tục.
  - `transferErrorStillLaunches`: đích chưa đăng nhập, có phiên mang theo → vẫn `launch`, kết quả `.done` với mọi phiên `.failed("Hãy mở profile này và đăng nhập một lần trước")`.
  - `defaultProfileLaunchesWithoutFlag`: target `dataDir nil` → `launch(dataDir: nil)`.
- [ ] **Step 2:** `swift test --filter SwitchCoordinatorTests` → FAIL.
- [ ] **Step 3:** Implement; org đích = `ClaudeDataDir.orgUuid(cookieOrg: try? cookies.read(dataDir:).lastActiveOrg)`.
- [ ] **Step 4:** `swift test` (toàn bộ) → PASS.
- [ ] **Step 5:** Commit `feat: SwitchCoordinator`.

### Task 8: SwiftUI app + đóng gói

**Files:**
- Create: `Sources/ClaudeSwitch/AppModel.swift`, `MenuView.swift`, `ManageWindow.swift`, `scripts/Info.plist`, `scripts/build-app.sh`
- Modify: `Sources/ClaudeSwitch/ClaudeSwitchApp.swift`

**Interfaces:**
- Consumes: mọi type ở Core.
- Produces: `@MainActor final class AppModel: ObservableObject { @Published profiles: [Profile]; @Published running: Profile?; @Published selected: Profile.ID?; @Published usage: [Profile.ID: ProfileUsageState]; @Published sessions: [SessionInfo]; func refreshUsage(force: Bool); func requestSwitch(carrying: [SessionInfo]); func addProfile(name:); func rename(_:to:); func remove(_:deleteData:) }`

- [ ] **Step 1:** `AppModel`: timer 300s gọi `refreshUsage(force: false)`; `refreshUsage` chạy song song cho mọi profile; `running` cập nhật khi mở menu và khi nhận `NSWorkspace.didLaunchApplicationNotification` / `didTerminateApplicationNotification`.
- [ ] **Step 2:** `MenuView` (MenuBarExtra `.menuBarExtraStyle(.window)`) đúng bố cục spec §5: dòng profile `✓`/tên/`5h x% (reset HH:mm) · Tuần y%`, màu theo ngưỡng, `⚠︎ cũ · HH:mm` khi `source == .file`, `—` khi `unavailable`, `chưa đăng nhập`; nút `↻`, `Switch`, `Switch & mang phiên…`, `Quản lý profile…`, `Thoát`. `onAppear` → `refreshUsage(force: false)`.
- [ ] **Step 3:** Hộp xác nhận trước khi quit Claude: "Claude sẽ được tắt, các phiên đang chạy sẽ dừng." (`NSAlert`); `.needsForceQuit` → NSAlert "Claude chưa tắt. Buộc tắt?" [Buộc tắt] [Huỷ]; kết quả transfer có `.failed` → NSAlert liệt kê title phiên lỗi.
- [ ] **Step 4:** `ManageWindow` (`Window("Claude Switch", id: "manage")`): tab **Mang phiên** (List checkbox, ẩn archived mặc định + Toggle "Hiện phiên đã archive", ô tìm theo title/cwd, Picker profile đích, nút "Switch & mang theo"); tab **Profile** (thêm, đổi tên inline, xoá với NSAlert hỏi xoá cả dữ liệu, nút "Mở để đăng nhập").
- [ ] **Step 5:** `scripts/Info.plist` (`CFBundleIdentifier com.luke.claudeswitch`, `LSUIElement true`, `LSMinimumSystemVersion 14.0`); `scripts/build-app.sh`: `swift build -c release` → tạo `build/ClaudeSwitch.app/Contents/{MacOS,Info.plist}` → `codesign --force --sign - build/ClaudeSwitch.app`. Chạy script → `build/ClaudeSwitch.app` tồn tại, `codesign -v build/ClaudeSwitch.app` không báo lỗi.
- [ ] **Step 6:** Mở `build/ClaudeSwitch.app` → icon menu bar xuất hiện, menu hiện profile mặc định với usage live (so với Settings › Usage). Không bấm Switch ở bước này (sẽ tắt phiên Claude đang chạy).
- [ ] **Step 7:** Commit `feat: menu bar UI and app bundle`.

### Task 9: Kiểm thử tay với 2 account (người dùng tham gia)

Gộp spike S1 và S3 của spec — cần người dùng đăng nhập account 2 và chấp nhận việc Claude bị tắt.

- [ ] **Step 1 (S3):** Tab Profile → thêm "Account 2" → "Mở để đăng nhập". Người dùng đăng nhập account 2. Kiểm tra: menu bar hiện ✓ Account 2; usage Account 1 vẫn live (đọc cookie profile không chạy); quay lại Account 1 không phải đăng nhập.
- [ ] **Step 2 (S1):** Từ Account 1, "Switch & mang phiên…" chọn 1 phiên → sang Account 2 → phiên hiện trên sidebar và gửi được tin nhắn mới. Nếu không hiện hoặc lỗi: ghi lại hành vi, so sánh `local_*.json` với một phiên tạo mới ở Account 2 để tìm trường cần sửa, báo người dùng trước khi sửa code.
- [ ] **Step 3:** Switch ngược lại hai chiều; chuyển nhiều phiên một lúc; thử phiên đã tồn tại ở đích (hiện "đã có").
- [ ] **Step 4:** Ghi kết quả vào spec §9 và commit `docs: record manual test results`.
