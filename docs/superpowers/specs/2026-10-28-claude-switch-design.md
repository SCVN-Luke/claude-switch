# ClaudeSwitch — Design Spec

Ngày: 2026-10-28 · Trạng thái: chờ review

## 1. Mục tiêu

Người dùng có 2 account Claude và muốn chuyển Claude Desktop giữa chúng trong vài giây,
không logout/login, phòng khi một account hết usage.

Tiêu chí thành công:
- Chọn profile trên menu bar → Switch → Claude mở lại với account kia, không phải đăng nhập.
- Có thể mang các phiên Code đang làm sang profile mới để làm tiếp.
- Nhìn được mức usage gần nhất của từng profile để biết nên switch sang đâu.
- Đơn giản, miễn phí, chỉ dùng cá nhân trên macOS.

Môi trường hiện tại: macOS 26.6, Claude Desktop 4.29.0 (Electron), Swift có sẵn.

## 2. Phạm vi

**Có:**
1. Quản lý profile (thêm / đổi tên / xoá khỏi danh sách).
2. Switch profile từ menu bar.
3. Mang phiên Code (Claude Code trong Desktop) sang profile đích.
4. Hiện usage **hiện tại** của từng profile (kể cả profile không chạy), gọi cùng API mà
   Claude Desktop dùng; fallback về snapshot trong file khi API lỗi.

**Không:**
- Tự động switch khi hết quota.
- Chạy song song nhiều Claude cùng lúc.
- Chuyển hội thoại Chat tab (lưu trên server theo account, không chuyển được).
- Đồng bộ cloud, đa máy, Windows.

## 3. Cơ chế nền (đã khảo sát trên máy)

Claude Desktop là app Electron nên nhận `--user-data-dir=<path>`. Mỗi thư mục data là một
"profile" độc lập (cookie, token, cấu hình riêng).

Cấu trúc data dir mặc định `~/Library/Application Support/Claude/` liên quan:

| Đường dẫn | Nội dung |
|---|---|
| `config.json` → `lastKnownAccountUuid` | UUID account đăng nhập gần nhất |
| `claude-code-sessions/<accountUuid>/<orgUuid>/local_<id>.json` | Metadata một phiên Code (title, cwd, cliSessionId, model, …) — đây là thứ sidebar hiển thị |
| `plan-usage-history.json` | Mảng `samples` `{t, org, u:{fh, sd, xu?}}` — snapshot usage |
| `scratch-workspaces/<acc>/<org>/…` | Thư mục làm việc tạm của một số phiên |

Transcript phiên nằm **ngoài** data dir: `~/.claude/projects/<cwd-mã-hoá>/<cliSessionId>.jsonl`,
nên mọi profile đều dùng chung → chuyển phiên chỉ cần copy file metadata.

### Usage (đọc từ mã nguồn Claude Desktop 4.29.0)

- Claude Desktop gọi `GET https://claude.ai/api/organizations/{orgUuid}/usage` bằng
  `net.fetch` của Electron, xác thực bằng cookie `sessionKey` của claude.ai trong profile.
- Response (rút gọn):
  ```json
  { "five_hour": {"utilization": 48, "resets_at": "ISO8601|null"},
    "seven_day": {"utilization": 33, "resets_at": "…"},
    "seven_day_opus": …, "seven_day_sonnet": …,
    "extra_usage": {"is_enabled": true, "monthly_limit": …, "used_credits": …, "utilization": …},
    "limits": [ {"kind": "…", "group": "…", "percent": 48, "resets_at": "…"} ] }
  ```
- `plan-usage-history.json` chỉ là log phụ: `fh`=five_hour, `sd`=seven_day, `xu`=extra_usage.utilization,
  ghi tối đa 1 mẫu / 4,5 phút / org, giữ 30 ngày, và **chỉ khi Claude tự poll** — poll nền bị tạm dừng
  nếu người dùng lâu không mở menu tray của Claude. Vì vậy file có thể cũ hàng giờ (đã thấy: file
  ghi 07:33, thực tế 5h đang 48%). Chỉ dùng làm fallback.
- Cookie lưu trong `<dataDir>/Cookies` (SQLite, bảng `cookies`, meta version 24). Giá trị mã hoá
  kiểu Chromium macOS: tiền tố `v10`, AES-128-CBC, IV = 16 dấu cách, khoá = PBKDF2-HMAC-SHA1(mật khẩu
  Keychain service `Claude Safe Storage` / account `Claude Key`, salt `saltysalt`, 1003 vòng, 16 byte);
  plaintext (version ≥ 24) có 32 byte SHA-256 của host đứng đầu, cần bỏ đi.
  Khoá Keychain dùng chung cho mọi `--user-data-dir` → một khoá giải được cookie của mọi profile.

## 4. Kiến trúc

App Swift/SwiftUI, macOS 14+, `LSUIElement` (không hiện Dock). Một target app + một
Swift package `ClaudeSwitchCore` chứa logic để unit test.

```
ClaudeSwitch.app
├── MenuBarExtra (UI)        — danh sách profile, usage, nút Switch, mở cửa sổ phụ
├── SessionsWindow (UI)      — chọn phiên để mang qua, quản lý profile
└── ClaudeSwitchCore (logic, không phụ thuộc UI)
    ├── ProfileStore         — đọc/ghi profiles.json
    ├── ClaudeDataDir        — đọc accountUuid, orgUuid, liệt kê phiên, đọc usage từ một data dir
    ├── SessionTransfer      — copy phiên giữa hai ClaudeDataDir
    ├── ClaudeLauncher       — quit / launch Claude.app với data dir
    ├── CookieReader         — giải mã cookie sessionKey của một data dir
    └── UsageClient          — gọi API usage, parse response
```

Mỗi unit chỉ nhận đường dẫn qua init → test được bằng thư mục giả trong temp.

### 4.1 ProfileStore
- File: `~/Library/Application Support/ClaudeSwitch/profiles.json`
  ```json
  { "profiles": [ { "id": "uuid", "name": "Account 1", "dataDir": null },
                  { "id": "uuid", "name": "Account 2", "dataDir": "…/ClaudeSwitch/Profiles/<id>" } ],
    "activeProfileId": "uuid" }
  ```
- `dataDir: null` = data dir mặc định của Claude (không truyền flag). Lần chạy đầu tự tạo
  profile mặc định này, không di chuyển dữ liệu hiện có.
- Thêm profile → tạo thư mục `Profiles/<id>/` rỗng. Xoá profile → chỉ xoá khỏi danh sách;
  hỏi riêng có xoá thư mục data không (mặc định không). Không cho xoá profile mặc định.

### 4.2 ClaudeDataDir
- `accountUuid`: từ `config.json.lastKnownAccountUuid`; nil nếu chưa đăng nhập.
- `orgUuid`: ưu tiên cookie `lastActiveOrg` (qua `CookieReader`); nếu không có → thư mục con
  duy nhất dưới `claude-code-sessions/<accountUuid>/`; nếu nhiều → `org` của sample usage mới
  nhất; vẫn không xác định → nil.
- `sessions()`: parse các `local_*.json`, trả về `{sessionId, title, cwd, lastActivityAt, isArchived, fileURL}`.
  Bỏ qua file parse lỗi (log lại), không crash.
- `snapshotUsage()`: sample mới nhất (theo `t`) khớp `orgUuid` → `UsageSnapshot` (fallback).
- Chỉ **đọc**; không đọc/ghi các key `oauth:*` trong `config.json`.

### 4.5 CookieReader
`sessionKey(for dataDir: URL) throws -> String`
- Copy `Cookies` (+ `Cookies-journal` nếu có) vào thư mục tạm rồi mở bằng SQLite3 (C API có sẵn
  trên macOS, không thêm dependency) — tránh đụng file đang bị Claude khoá.
- Lấy dòng `host_key IN ('.claude.ai','claude.ai') AND name='sessionKey'`, giải mã theo §3.
- Mật khẩu Keychain đọc bằng `SecItemCopyMatching` (service `Claude Safe Storage`), cache trong bộ
  nhớ suốt phiên chạy app. Lần đầu macOS hiện hộp thoại hỏi quyền — người dùng chọn "Always Allow".
- Cookie và khoá **không bao giờ** được ghi ra đĩa, log hay UI.
- Hàm giải mã thuần (`decrypt(encrypted:password:hostKey:)`) tách riêng để unit test bằng vector
  tự tạo (mã hoá ngược bằng CommonCrypto trong test).

### 4.6 UsageClient
`fetchUsage(orgUuid:, sessionKey:) async throws -> UsageSnapshot`
- `GET https://claude.ai/api/organizations/{orgUuid}/usage`, header `Cookie: sessionKey=…`,
  `Accept: application/json`, User-Agent giống Claude Desktop. Timeout 15s.
- Parse dễ dãi: `five_hour`, `seven_day` (bắt buộc hiển thị), `extra_usage` (tuỳ chọn); trường lạ bỏ qua.
- `UsageSnapshot = {fiveHourPct, fiveHourResetsAt?, weeklyPct, weeklyResetsAt?, extraPct?, fetchedAt, source: .live|.file}`.
- Lịch: làm mới khi mở menu (nếu dữ liệu > 60s) và nền mỗi 5 phút cho mọi profile đã đăng nhập.
  Không dùng `skip_spend`. Lỗi (401/403/timeout/schema) → dùng `snapshotUsage()` và đánh dấu "cũ".
- `orgUuid` cho API: như §4.2; nếu nil thì không gọi.

### 4.3 SessionTransfer
`transfer(sessions, from: ClaudeDataDir, to: ClaudeDataDir) -> [Result]`
- Yêu cầu đích có `accountUuid` + `orgUuid`; nếu không → lỗi "Hãy mở profile này và đăng nhập một lần trước".
- Với mỗi phiên: copy JSON nguyên vẹn sang `to/claude-code-sessions/<acc>/<org>/local_<id>.json`.
  Giữ nguyên `sessionId`, `cliSessionId`, `cwd` (đường dẫn tuyệt đối vẫn tồn tại trên đĩa).
- Nếu file đích đã tồn tại → bỏ qua, báo "đã có".
- Copy, không move: phiên gốc giữ nguyên ở profile cũ.
- Các trường gắn với org cũ (ví dụ `enabledMcpTools`) giữ nguyên; Spike S1 sẽ quyết định
  có cần xoá/sửa trường nào để Claude nhận phiên không.
- Ghi atomically (ghi file tạm rồi rename). Lỗi một phiên không chặn các phiên khác.

### 4.4 ClaudeLauncher
- Tìm Claude.app qua bundle id (`NSWorkspace.urlForApplication(withBundleIdentifier:)`),
  fallback `/Applications/Claude.app`.
- `isRunning`: `NSRunningApplication` theo bundle id.
- `quit()`: `terminate()` → chờ tối đa 10s → nếu còn chạy, trả về `.stillRunning` để UI hỏi
  có `forceTerminate()` không.
- `launch(profile)`: `NSWorkspace.openApplication` với `arguments = ["--user-data-dir=…"]`
  (bỏ trống cho profile mặc định), `createsNewApplicationInstance = true`.
- Nhận diện profile đang chạy: đọc tham số dòng lệnh của tiến trình Claude chính
  (`sysctl KERN_PROCARGS2` theo pid). Có `--user-data-dir=X` → profile có `dataDir == X`;
  không có → profile mặc định. Claude không chạy → không profile nào có dấu ✓.
  `activeProfileId` chỉ dùng làm giá trị dự phòng khi không đọc được tham số.

## 5. UI

### Menu bar (MenuBarExtra, style `.window`)
```
 Claude Switch
 ───────────────────────────────
 ✓ Account 1        5h 48% (reset 13:20) · Tuần 33%
   Account 2        5h 80% (reset 11:05) · Tuần 91%   ⚠︎ cũ · 07:33
 ───────────────────────────────
 [ Switch ]   [ Switch & mang phiên… ]
 Quản lý profile…            Thoát
```
- Click dòng để chọn; Switch bật khi chọn profile khác profile đang chạy.
- Usage tô màu: < 70% bình thường, 70–90% vàng, > 90% đỏ. Không có dữ liệu → "—".
- Số live hiện kèm giờ reset; số lấy từ file (fallback) hiện "⚠︎ cũ · <giờ lấy mẫu>".
- Nút ↻ nhỏ để làm mới usage ngay.
- Profile chưa đăng nhập hiện nhãn "chưa đăng nhập".

### Cửa sổ phụ
- Tab **Mang phiên**: danh sách phiên của profile hiện tại (title, thư mục, lần hoạt động cuối),
  ẩn phiên archived mặc định, ô tìm kiếm, checkbox. Chọn profile đích → "Switch & mang theo".
- Tab **Profile**: thêm / đổi tên / xoá; nút "Mở để đăng nhập" (launch profile mới lần đầu).

## 6. Luồng chính

**Switch:**
1. Claude đang chạy → hộp xác nhận "Claude sẽ được tắt, các phiên đang chạy sẽ dừng".
2. `quit()`; nếu `.stillRunning` → hỏi buộc tắt hay huỷ.
3. (Nếu có phiên được chọn) `SessionTransfer` — chạy **sau** khi Claude cũ đã tắt và trước khi
   mở Claude mới, để không bên nào đang ghi file.
4. `launch(target)`; lưu `activeProfileId`.
5. Lỗi chuyển phiên → vẫn mở profile đích, hiện tóm tắt phiên nào lỗi.

**Thêm profile:** nhập tên → tạo thư mục → hỏi "Mở để đăng nhập ngay?" → luồng Switch.

## 7. Xử lý lỗi

| Tình huống | Xử lý |
|---|---|
| Không thấy Claude.app | Thông báo, nút mở thư mục Applications |
| Claude không tắt trong 10s | Hỏi buộc tắt / huỷ |
| Đích chưa đăng nhập (không có account/org) | Chặn chuyển phiên, gợi ý đăng nhập trước; vẫn cho Switch thường |
| JSON phiên/usage hỏng hoặc đổi format | Bỏ qua mục đó, ghi log, UI hiện "—" |
| Người dùng từ chối quyền Keychain | Không gọi API nữa trong phiên chạy; dùng snapshot file, hiện gợi ý cấp quyền |
| API usage 401/403 (hết phiên đăng nhập, Cloudflare chặn) | Fallback snapshot, đánh dấu "cũ", log mã lỗi |
| Ghi file lỗi | Không xoá gì, báo lỗi theo từng phiên |

Log: `~/Library/Logs/ClaudeSwitch.log` (os_log + file).

## 8. Rủi ro & quyết định

- **Format nội bộ có thể đổi** khi Claude cập nhật → chuyển phiên / usage có thể hỏng; switch
  profile không bị ảnh hưởng. Parser dễ dãi (bỏ qua key lạ), lỗi hiển thị rõ ràng.
- **Usage live dùng cookie đăng nhập và API không công khai.** App đọc cookie `sessionKey`
  của chính người dùng trên chính máy này, chỉ gửi tới `claude.ai`, không lưu/log. Rủi ro:
  API hoặc cách mã hoá cookie đổi khi Claude cập nhật; Cloudflare có thể chặn request không
  phải từ trình duyệt (claude.ai có cookie `cf_clearance`). Khi đó app tự rơi về snapshot file.
- **Cách khác đã cân nhắc:** ép Claude Desktop tự poll để cập nhật file (mở menu tray của nó)
  — chỉ được cho profile đang chạy và phải giả lập click qua Accessibility, dễ vỡ → không dùng.
- **Phiên Code đang chạy bị ngắt** khi switch → luôn xác nhận trước khi tắt. Phiên bị ngắt
  vẫn còn trên sidebar profile cũ và có thể được mang sang profile mới.
- **Chữ ký / Gatekeeper:** app tự build, ký ad-hoc, chạy cục bộ; không notarize.

## 9. Spike trước khi code (bắt buộc)

- **S1 – Chuyển phiên:** tạo profile 2, đăng nhập account 2, copy tay 1 file `local_*.json`
  sang `claude-code-sessions/<acc2>/<org2>/`, mở profile 2 → phiên có hiện trên sidebar và
  tiếp tục chat được không? Ghi lại trường nào cần sửa. Nếu thất bại → bỏ tính năng chuyển
  phiên khỏi v1, báo lại người dùng.
- **S2 – Usage live:** script Swift nhỏ (`scripts/spike-usage.swift`) giải mã `sessionKey` của
  profile mặc định, gọi API usage và **chỉ in** `five_hour`/`seven_day` (không in cookie).
  Người dùng tự chạy trong Terminal (hộp thoại Keychain hiện cho họ) và so với Settings › Usage.
  Nếu bị Cloudflare chặn → thử thêm header giống Electron; vẫn chặn → v1 chỉ dùng snapshot file.
  **Kết quả 2026-10-28: ĐẠT.** URLSession + Cookie `sessionKey` + UA kiểu Electron → HTTP 200,
  `five_hour` 50%, `seven_day` 39%, khớp UI Claude. Org lấy từ cookie `lastActiveOrg` đúng.
  `extra_usage.utilization` là % (26.275), `used_credits`/`monthly_limit` tính bằng cent.
  **Kết quả 2026-10-28: ĐẠT.** Copy nguyên `local_*.json` (không sửa trường nào) sang
  `claude-code-sessions/<acc2>/<org2>/` → phiên hiện trên sidebar profile 2, chat tiếp được với
  đủ context (transcript dùng chung ở `~/.claude`). Claude tự cập nhật các trường runtime
  (`lastActivityAt`, `toolSurfaceSnapshot`, `remoteControlAutoEligible`…) sau khi mở.
- **S3 – Flag:** xác nhận `--user-data-dir` qua `NSWorkspace.openApplication` thực sự tách
  profile (không dùng chung đăng nhập với profile mặc định).
  **Kết quả 2026-10-28: ĐẠT.** Profile 2 chạy với `--user-data-dir=…/Profiles/<id>`, đăng nhập
  account khác (account UUID khác), profile mặc định vẫn giữ account cũ.

## 10. Kiểm thử

- Unit test (`swift test`) cho `ProfileStore`, `ClaudeDataDir`, `SessionTransfer` trên fixture
  thư mục giả: profile chưa đăng nhập, nhiều org, JSON hỏng, file đích đã tồn tại, usage rỗng.
- `CookieReader.decrypt` test bằng vector tự mã hoá; `UsageClient` test parse trên JSON mẫu
  (đủ trường, thiếu trường, trường lạ) với `URLProtocol` giả.
- `ClaudeLauncher` bọc sau protocol để test luồng Switch bằng fake.
- Kiểm thử tay với 2 account thật: switch hai chiều, chuyển 1 và nhiều phiên, usage hiển thị.

## 11. Cấu trúc repo dự kiến

```
claude-switch/
├── Package.swift                 (ClaudeSwitchCore + tests)
├── Sources/ClaudeSwitchCore/…
├── Tests/ClaudeSwitchCoreTests/…
├── App/ (SwiftUI app, build bằng script swiftc/xcodebuild → ClaudeSwitch.app)
├── scripts/build-app.sh
└── docs/superpowers/specs/2026-10-28-claude-switch-design.md
```
