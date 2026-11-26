# Eave

A native macOS menu bar manager with Notch integration, built with pure Swift (`AppKit` + `SwiftUI`) and zero third-party dependencies.

- **Minimum macOS**: macOS 15.0 (Sequoia), tuned for macOS 26 (Tahoe) with Liquid Glass support.
- **Design Document**: See [docs/DESIGN.md](docs/DESIGN.md) (Chinese).

## Features

- **Three-Section Menu Bar Management**: Organize menu bar items into *Visible*, *Hidden*, and *Always-Hidden* sections using lightweight separator status items. Supports click toggle, `Option+Click`, scroll-wheel gestures, hover expand, global shortcuts, and auto-rehide.
- **Notch Peek for Hidden Apps**: Monitors Dock notification badges (`AXStatusLabel`) and menu bar attribute changes for hidden or watched apps, smoothly peeking from the MacBook notch with click-to-open actions.
- **Notch Bar**: Expands downward directly from the physical notch (or a top floating pill on non-notched displays) to reveal hidden menu bar items with on-demand icon capture and click forwarding.
- **Quick Menu Bar Search**: Press `⌥⌘K` to fuzzy-search and trigger any visible or hidden menu bar item from the keyboard.
- **NotchBridge (Local Automation API)**: Send custom peeks or ambient indicators to the notch from any shell script, CLI, or your own apps via URL Scheme (`eave://notify?...`) or `DistributedNotificationCenter`.
- **Menu Bar Spacing Control**: Adjust system `NSStatusItemSpacing` and selection padding with one-click reset.

## Install

Requires macOS 15 or newer.

```bash
brew tap abcdlsj/tap
brew trust abcdlsj/tap  # Homebrew refuses to load casks from an untrusted third-party tap
brew install --cask eave
```

Or download the dmg from [Releases](https://github.com/abcdlsj/eave/releases). Release builds are
ad-hoc signed and not notarised: a browser download is blocked by Gatekeeper on first launch
(right-click → Open), while a Homebrew install carries no quarantine attribute and just runs.

On first launch grant Accessibility access in System Settings → Privacy & Security →
Accessibility; without it Eave cannot move or click other apps' menu bar items.

## Build & Run

Requires Xcode 26 (the build uses the macOS 26 SDK for Liquid Glass; the app itself
still deploys to macOS 15) and `xcodegen`.

```bash
# Generate icons and Xcode project
swift scripts/generate-icons.swift
xcodegen generate

# Build and test
xcodebuild -project Eave.xcodeproj -scheme Eave -configuration Debug build
xcodebuild -project Eave.xcodeproj -scheme Eave -configuration Debug test
```

## Release

Tagging `vX.Y.Z` runs [`.github/workflows/release.yml`](.github/workflows/release.yml): it builds
the universal dmg, publishes the GitHub release, and attaches an `eave.rb` cask generated from the
real dmg checksum. Copy that file into `abcdlsj/homebrew-tap`'s `Casks/`.

Bump `MARKETING_VERSION` in [project.yml](project.yml) before tagging; the workflow fails when the
tag and that version disagree. The same packaging runs locally:

```bash
scripts/package-release.sh 0.2.0                        # dmg + zip in dist/
scripts/write-cask.sh 0.2.0 dist/eave_0.2.0_darwin_universal.dmg  # dist/eave.rb
```

Set `EAVE_SIGN_IDENTITY` to sign with a Developer ID instead of ad-hoc.

## NotchBridge CLI Example

```bash
./scripts/eave-notify --title "Build Complete" --subtitle "eave 0.1.0" --badge "OK" --symbol "checkmark.circle.fill"
```

Or via URL scheme directly:

```bash
open "eave://notify?title=Deployment+Done&subtitle=production&badge=1&symbol=sparkles&duration=5"
```
