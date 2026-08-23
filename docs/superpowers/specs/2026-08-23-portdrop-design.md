# PortDrop — Design Spec (2026-08-23)

## Purpose
A macOS 26 menu-bar utility that lists every process listening on a local TCP port, shows it with rich app iconography, offers a one-click link to the service (http/https/ftp/ssh/db URLs), and can kill the process — escalating to admin via the standard macOS auth dialog when the process isn't owned by the current user.

## Decisions (from brainstorming)
- Scope: **listening TCP ports only** (no established connections, no UDP).
- Privileges: own processes killed directly; others via `osascript ... with administrator privileges`. No privileged helper in v1.
- UI: `MenuBarExtra(.window)` popover panel, Liquid Glass styling.
- Kill: two-step (click → "Confirm" for 3 s → click). Option-click = SIGKILL.
- Tooling: XcodeGen-generated Xcode project, Swift 6, SwiftUI, macOS 26 target, no App Sandbox, Hardened Runtime, Developer ID signed + notarized via `Scripts/release.sh`.
- Extras: search/filter, copy actions, menu-bar port count, new-port notification.

## Architecture

```
PortDropApp (MenuBarExtra)
 └─ PortMonitor (@Observable, polling)      ── uses ─▶ PortScanner ── runs ─▶ lsof
      │                                               ProcessInfoResolver (icons/names)
      │                                               ServiceClassifier (URLs)
      └─ PanelView ─▶ PortRowView ─▶ ProcessKiller (kill / osascript)
 Settings: LaunchAtLogin (SMAppService), notifications toggle (UserDefaults)
```

### Models
```swift
struct ListeningPort: Identifiable, Hashable {
  let id: String          // "\(pid):\(port)"
  let pid: pid_t
  let processName: String // from lsof 'c' field
  let user: String
  let port: UInt16
  let bindAddress: String // "*", "127.0.0.1", "::1" ...
  let ipVersions: Set<IPVersion>
}
struct ServiceInfo { let kind: ServiceKind; let url: URL? }   // kind: http, https, ftp, ssh, postgres, mysql, redis, mongo, vnc, smb, afp, tcp
struct ProcessPresentation { let displayName: String; let icon: NSImage; let bundlePath: String? }
```

### PortScanner
- Command: `/usr/sbin/lsof -iTCP -sTCP:LISTEN -P -n -F pcLnT` (p=pid, c=command, L=login name, n=name host:port, T=TCP info).
- Parses line-oriented `-F` output: lines prefixed with `p` start a new process block; each `n` line yields one listening socket.
- Dedupes: same pid+port across IPv4/IPv6 → one `ListeningPort` with both versions.
- Failure (non-zero exit with no output, binary missing) → throws `ScanError`; monitor surfaces it as a banner.
- Pure parser function `parse(_ output: String) -> [ListeningPort]` for unit tests.

### ProcessInfoResolver
- `proc_pidpath(pid)` → executable path → walk up to `.app` bundle if present.
- If `NSRunningApplication(processIdentifier:)` exists → its `localizedName` + `icon`.
- Else if bundle path → `NSWorkspace.shared.icon(forFile:)`.
- Else SF Symbol fallback chosen by ServiceKind (`globe`, `server.rack`, `cylinder`, `terminal`, `network`).
- Results cached per pid.

### ServiceClassifier
Port → kind/URL table (first match wins; process name used as tie-breaker, e.g. `postgres`, `redis-server`, `mysqld`, `mongod`, `sshd`, `ftpd`):
| ports | kind | url |
|---|---|---|
| 80, 3000-3010, 4000, 4200, 5000, 5173, 5174, 8000-8010, 8080-8090, 8888, 9000, 1313, 4321 | http | `http://localhost:PORT` |
| 443, 8443 | https | `https://localhost:PORT` |
| 21 | ftp | `ftp://localhost` |
| 22 | ssh | `ssh://localhost` |
| 5432 | postgres | `postgresql://localhost:5432` |
| 3306 | mysql | `mysql://localhost:3306` |
| 6379 | redis | `redis://localhost:6379` |
| 27017 | mongo | `mongodb://localhost:27017` |
| 5900 | vnc | `vnc://localhost` |
| 445 | smb | `smb://localhost` |
| 548 | afp | `afp://localhost` |
Unknown port → async HTTP probe (`HEAD http://localhost:PORT`, 300 ms timeout, any HTTP response incl. 4xx/5xx counts) → http; otherwise `.tcp` with no URL. Probe results cached per pid:port.
Bind address `127.0.0.1`/`::1`/`*` all map to `localhost`; a specific non-loopback address is used verbatim.

### ProcessKiller
```swift
func kill(_ port: ListeningPort, force: Bool) async throws
```
- `getpwuid(getuid())` name == `port.user` (or pid owned check via `kill(pid, 0)` succeeding) → `Darwin.kill(pid, force ? SIGKILL : SIGTERM)`.
- `EPERM` or non-owned → run `/usr/bin/osascript -e 'do shell script "/bin/kill -SIG PID" with administrator privileges'`. User cancel (exit code 1, "User canceled") → `KillError.cancelled`, handled silently.
- `ESRCH` → success (already gone).
- After kill, monitor refreshes immediately.

### PortMonitor
- `@Observable @MainActor final class`; properties: `ports`, `lastError`, `isScanning`, `searchText`, `filteredPorts`.
- Polls every 2 s while panel visible, 10 s otherwise (`Task` loop, cancelled on deinit).
- Diffs id sets; new ids after the first scan → `UNUserNotificationCenter` local notification "New service on port N (name)" if enabled.
- Exposes `count` for the menu bar label.

### UI
- `MenuBarExtra { PanelView } label: { single template image of network glyph + count, cached per count, with accessibility label }` with `.menuBarExtraStyle(.window)`.
- `PanelView`: width 420, max height 560, `.glassEffect(.regular, in: .rect(cornerRadius: 20))` container; header (title, search `TextField`, refresh & gear `Menu`); `ScrollView` of `PortRowView`; empty-state; error banner.
- `PortRowView`: icon 28 pt, name (headline) + kind chip + "user · PID" (caption, secondary; bind address in the tooltip), kind chip (capsule, tinted per kind), port in `.monospacedDigit().bold()`, Open button (`arrow.up.right.square`) when URL, Kill button (`xmark.octagon.fill`); kill state machine `idle → confirming(3 s timer) → killing → done`. Row removal animated with `.transition(.opacity.combined(with: .move(edge:.leading)))`.
- Context menu: Open, Copy URL, Copy PID, Copy host:port, Reveal in Finder (if bundle path), Force Kill.
- Settings `Menu`: Launch at Login toggle, New-port notifications toggle, Quit.

### Error handling
- Scan error → banner with message; list keeps last good data.
- Auth cancelled → revert button, no alert.
- Kill failure → inline red caption under row for 4 s.

### Testing
- `PortScannerTests`: fixture outputs (IPv4 only, v4+v6 twin, root-owned sshd, multiple ports one process, empty output).
- `ServiceClassifierTests`: table mapping, process-name tiebreak, bind address → host.
- `PortMonitorTests`: diff yields new ids correctly.
- Manual smoke per spec: `python3 -m http.server 8765` → appears, Open works, Kill removes.

### Build & release
- `project.yml` (XcodeGen): target `PortDrop`, macOS 26.0, `LSUIElement = YES`, entitlements: hardened runtime, no sandbox. Test target `PortDropTests`.
- `Scripts/release.sh`: `xcodegen`, `xcodebuild archive`, export with Developer ID (team 88ZPCYS252), `notarytool submit --wait --keychain-profile PortDrop`, `stapler staple`, zip to `dist/`. Requires a stored notarytool profile; script prints instructions if missing.
