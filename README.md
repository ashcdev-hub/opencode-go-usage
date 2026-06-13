# Opencode Go Usage

A lightweight macOS menu bar app that displays your [OpenCode GO](https://opencode.ai/go) subscription usage in real time. Rolling, weekly, and monthly limits with progress bars, no more checking a browser tab to see when your limits reset.

Inspired by needing to easily view usage stats that I wasn't seeing in [Opencode Stats](https://github.com/fayazara/opencode-stats) due to auth reasons.

## Features

- **Menu bar indicator** — shows a "GO" status item with a chart icon in your menu bar
- **Right-click context menu** — right-click the menu bar icon for About, Sign Out, and Quit
- **About window** — app info, copyright, MIT license, and link to the GitHub repo
- **Live usage data** — scrapes your OpenCode GO workspace page to display rolling, weekly, and monthly usage percentages with progress bars
- **Auto-refresh** — data refreshes automatically every 5 minutes (when logged in and idle)
- **Manual refresh** — click the refresh button for an instant (~1s) data refresh
- **Background operation** — runs as an `LSUIElement` (no Dock icon), purely menu bar–based
- **Session persistence** — caches usage data locally so the popover shows meaningful data immediately on launch while the hidden web view re-authenticates
- **Idle-friendly** — the hidden web view is torn down between scrapes so the app sits at near-baseline memory when you're not looking at it

## Installation

### Download

1. Download the latest [Release](https://github.com/ashcdev-hub/opencode-go-usage/releases)
2. Unzip and move `Opencode Go Usage.app` to your Applications folder
3. When the security warning appears, go to **System Settings → Privacy & Security** → click **Open Anyway** next to the blocked app message

The app is self-signed so macOS Gatekeeper will block it on first launch. Either follow the guidance above or remove the quarantine flag:

```bash
xattr -d com.apple.quarantine /Applications/Opencode\ Go\ Usage.app
```
## Project Structure

```
GoUsage/
├── GoUsage/
│   ├── GoUsageApp.swift        # App entry, AppDelegate, AuthState, webview lifecycle
│   ├── MenuBarDropdown.swift    # SwiftUI popover UI, NSHostingController content
│   ├── UsageScraper.swift       # JS scraping logic, data model, cache management
│   ├── UsageMeter.swift         # UsageMeter data model (stable id by label)
│   ├── Info.plist               # App config (LSUIElement)
│   ├── GoUsage.entitlements     # Entitlements (sandbox disabled)
│   └── Assets.xcassets/         # App icon assets
├── OpencodeGoUsage.xcodeproj/   # Generated Xcode project
├── project.yml                  # XcodeGen project specification
├── LICENSE                      # MIT License
└── README.md
```

### Building from Source

#### Prerequisites

- macOS 14.4+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for regenerating the Xcode project)

### Build

```bash
# Install XcodeGen if needed
brew install xcodegen

# Generate the Xcode project
cd GoUsage
xcodegen generate

# Open in Xcode
open OpencodeGoUsage.xcodeproj
```

Then build and run from Xcode.

### Build via CLI

```bash
xcodebuild -project OpencodeGoUsage.xcodeproj \
           -scheme OpencodeGoUsage \
           -configuration Release \
           build
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Build and test on macOS 14.4+
5. Commit your changes (`git commit -m 'Add my feature'`)
6. Push to the branch (`git push origin feature/my-feature`)
7. Open a Pull Request

## License

MIT

## Author

Ash Eskrett
