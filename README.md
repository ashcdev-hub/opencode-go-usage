# Opencode Go Usage

A lightweight macOS menu bar app that displays your [OpenCode GO](https://opencode.ai/go) subscription usage in real time. Rolling, weekly, and monthly limits with progress bars, no more checking a browser tab to see when your limits reset.

Inspired by needing to easily view usage stats that I wasn't seeing in [Opencode Stats](https://github.com/fayazara/opencode-stats) due to auth reasons.

## Features

- **Menu bar indicator** — shows a "GO" status item with a chart icon in your menu bar
- **Live usage data** — scrapes your OpenCode GO workspace page to display rolling, weekly, and monthly usage percentages with progress bars
- **Auto-refresh** — data refreshes automatically every 5 minutes
- **Manual refresh** — click the refresh button for an instant (~1s) data refresh
- **Background operation** — runs as an `LSUIElement` (no Dock icon), purely menu bar–based
- **Session persistence** — caches usage data locally so the popover shows meaningful data immediately on launch while the hidden web view re-authenticates

## Installation

### Download

1. Download the latest [Release](https://github.com/ashcdev-hub/opencode-go-usage/releases)
2. Unzip and move `Opencode Go Usage.app` to your Applications folder

### Gatekeeper (Unsigned App)

The app is self-signed, so macOS Gatekeeper will block it on first launch. You have two options:

**Option A — Remove quarantine flag (simplest):**

```bash
xattr -d com.apple.quarantine /Applications/Opencode\ Go\ Usage.app
```

**Option B — Bypass via System Settings:**

1. Right-click `Opencode Go Usage.app` → select **Open**
2. When the security warning appears, go to **System Settings → Privacy & Security** → click **Open Anyway** next to the blocked app message

After launch, look for the GO icon in your menu bar.

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

Then build and run (⌘R) from Xcode.

### Build via CLI

```bash
xcodebuild -project OpencodeGoUsage.xcodeproj \
           -scheme OpencodeGoUsage \
           -configuration Release \
           build
```

## Configuration

### Adjusting Refresh Interval

Change the timer interval in `GoUsageApp.swift`:

```swift
refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { ... }
```

Value is in seconds (300 = 5 minutes).

### Adjusting Scrape Timing

In `GoUsageApp.swift`:

- `scrapeDelay`: Initial delay before first scrape attempt after page load (default: 4 seconds). Only applies to auto-refresh and initial load — manual refresh skips this and scrapes immediately.
- `maxScrapeRetries`: Maximum number of scrape attempts (default: 20)
- Retry backoff: starts at 1.5s, increases by 0.5s each attempt, caps at 3.0s

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Build and test on macOS 14.4+
5. Commit your changes (`git commit -m 'Add my feature'`)
6. Push to the branch (`git push origin feature/my-feature`)
7. Open a Pull Request

### Code Style

- Follow existing Swift conventions in the project
- Use `// MARK: -` sections for code organization
- Keep SwiftUI views composable — extract subviews into separate structs
- Print debug logs with `=== ` prefix for easy filtering in Xcode console

## License

MIT

## Author

Ash Eskrett
