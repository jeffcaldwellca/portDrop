<p align="center">
  <img src="PortDrop/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@1x.png" width="128" alt="PortDrop icon">
</p>

<h1 align="center">PortDrop</h1>

<p align="center">
  A macOS menu-bar utility that lists every process listening on a local TCP port —<br>
  open it in one click, kill it in two.
</p>

<p align="center">
  <a href="https://github.com/jeffcaldwellca/portDrop/releases/latest"><img src="https://img.shields.io/github/v/release/jeffcaldwellca/portDrop?display_name=tag&sort=semver&label=release" alt="Latest release"></a>
  <a href="https://github.com/jeffcaldwellca/portDrop/actions/workflows/ci.yml"><img src="https://github.com/jeffcaldwellca/portDrop/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-0A84FF" alt="Requires macOS 26 or later">
  <img src="https://img.shields.io/badge/Swift-6-F05138" alt="Swift 6">
</p>

<p align="center">
  <a href="https://www.jeffcaldwell.ca/portDrop/"><b>Website</b></a> ·
  <a href="https://www.jeffcaldwell.ca/portDrop/releases/">Releases</a> ·
  <a href="https://github.com/jeffcaldwellca/portDrop/releases/latest">Download</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/panel-dark.png">
    <img src="docs/screenshots/panel-light.png" width="420" alt="The PortDrop panel: a searchable list of listening ports, each with the owning app's icon, a protocol chip, owner and PID, the port number, and Open and Kill buttons">
  </picture>
</p>

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask jeffcaldwellca/tap/portdrop
```

Or by hand:

1. Download `PortDrop-<version>.dmg` from the [latest release](https://github.com/jeffcaldwellca/portDrop/releases/latest).
2. Open it and drag **PortDrop** onto the **Applications** shortcut.

Then launch PortDrop from Applications or Spotlight. It lives in the menu bar — there's no Dock icon or window.

The app is signed with a Developer ID and notarized by Apple, so it opens without Gatekeeper warnings. Turn on **Launch at Login** from the ⚙︎ menu if you want it around permanently.

PortDrop keeps itself current with [Sparkle](https://sparkle-project.org): it checks for a new release once a day and offers to install it (⚙︎ → **Check for Updates…** to check now, or turn the automatic check off there). Homebrew installs update the same way; `brew upgrade --cask portdrop` also works.

**Requires macOS 26 Tahoe or later.** To verify a download: `shasum -a 256 -c PortDrop-<version>.dmg.sha256`.

## What you get

- **Every listening TCP port**, live — polled with `lsof` every 2 s while the panel is open and every 10 s in the background.
- **Real app icons** via `NSRunningApplication` / bundle lookup, with SF Symbol fallbacks for daemons and CLI tools.
- **Service detection** by process name and well-known port (HTTP/S, SSH, FTP, PostgreSQL, MySQL, Redis, MongoDB, VNC, SMB, AFP…), plus a quick `HEAD` probe so unknown ports that speak HTTP get an `http://` link too.
- **Open** (↗) launches the service URL in its default handler — `http://`, `ssh://`, `postgresql://`, and so on.
- **Kill** (⊗), two steps so you never nuke the wrong thing:
  1. Click ⊗ → it becomes a red **Confirm** (reverts on its own after 3 s).
  2. Click **Confirm** → `SIGTERM`. Hold **⌥** while confirming for `SIGKILL`.

  If the process belongs to root or another user, PortDrop escalates to the standard macOS administrator-password dialog instead of failing silently.
- **Search** by port, process, user, or protocol.
- **Right-click** a row for Open, Copy URL / PID / host:port, Reveal in Finder, Kill, and Force Kill.
- **Menu-bar badge**: the PortDrop mark plus the number of listening ports.
- **Optional notification** when a new port starts listening.
- **Launch at Login** via `SMAppService`.

Nothing leaves your Mac: PortDrop only talks to `127.0.0.1`/`::1` for the HTTP probe, and it has no analytics, telemetry, or network dependencies.

## Build from source

Requires **Xcode 26** and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open PortDrop.xcodeproj                                          # or, from the terminal:
xcodebuild -scheme PortDrop -destination 'platform=macOS' test
```

The app is intentionally **not sandboxed** — `lsof` and `kill` need direct process access. The `PortDrop` scheme runs the unit tests in `PortDropTests`; CI runs the same command with ad-hoc signing on every push and pull request.

Release, website, and branding workflows are documented in [docs/MAINTAINING.md](docs/MAINTAINING.md).
