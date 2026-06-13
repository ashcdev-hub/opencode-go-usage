# Opencode Go Usage

**Author:** Ash Eskrett

A lightweight macOS menu bar app that displays your [OpenCode GO](https://opencode.ai) subscription usage in real time. Rolling, weekly, and monthly limits with progress bars, no more checking a browser tab to see when your limits reset.

## Features

- **Menu bar indicator** — shows a "GO" status item with a chart icon in your menu bar
- **Live usage data** — scrapes your OpenCode GO workspace page to display rolling, weekly, and monthly usage percentages with progress bars
- **Auto-refresh** — data refreshes automatically every 5 minutes
- **Manual refresh** — click the refresh button in the popover to pull the latest data instantly
- **Background operation** — runs as an `LSUIElement` (no Dock icon), purely menu bar–based
- **Session persistence** — caches usage data locally so the popover shows meaningful data immediately on launch while the hidden web view re-authenticates

## How It Works

The app uses a hidden `WKWebView` to load your OpenCode GO workspace page in the background. After the page loads, JavaScript is injected to scrape the usage data from the DOM. The scraped data (labels, percentages, reset times) is parsed and displayed in a SwiftUI popover attached to the menu bar status item.

### Architecture

```
┌─────────────────────────────────────────────┐
│  NSStatusItem (menu bar "GO" button)        │
│  └── NSPopover (click to open)              │
│      └── MenuBarDropdown (SwiftUI)          │
│          ├── UsageRow × 3 (Rolling/Weekly)  │
│          └── Footer (refresh/signout/quit)  │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Hidden WKWebView (offscreen, 800×600)      │
│  └── Loads opencode.ai/workspace/{id}/go    │
│  └── JS scraper extracts usage data         │
│  └── Completion handler updates @Published  │
└─────────────────────────────────────────────┘
```

### Data Flow

1. **Launch** → cached usage is displayed immediately from `UserDefaults`
2. **Hidden web view** loads the workspace URL and authenticates via shared cookies
3. **`didFinish` delegate** fires after page load → 4 second delay → scrape attempts begin
4. **JS scraper** (`UsageScraper.scraperJS`) queries the DOM for `data-slot="usage-item"` elements
5. **Parsed data** updates `@Published meters` → SwiftUI re-renders the popover
6. **Auto-refresh timer** re-runs `loadWorkspace()` every 5 minutes

## Tech Stack

| Component | Technology |
|-----------|-----------|
| **Language** | Swift 5 |
| **UI Framework** | SwiftUI |
| **Web Engine** | WKWebView (WebKit) |
| **Build System** | XcodeGen (`project.yml`) → Xcode project |
| **Min macOS** | 14.4 (Sonoma) |
| **App Type** | Menu bar agent (`LSUIElement = true`) |
| **Sandboxing** | Disabled (required for shared cookie access) |

## Project Structure

```
GoUsage/
├── GoUsage/
│   ├── GoUsageApp.swift        # App entry point + AppDelegate (WKNavigationDelegate)
│   ├── MenuBarDropdown.swift    # SwiftUI popover UI (usage rows, footer, auth view)
│   ├── UsageScraper.swift       # JS scraping logic, data model, cache management
│   ├── UsageMeter.swift         # UsageMeter data model
│   ├── Info.plist               # App config (LSUIElement, ATS exceptions)
│   ├── GoUsage.entitlements     # Entitlements (sandbox disabled)
│   └── Assets.xcassets/         # App icon assets
├── OpencodeGoUsage.xcodeproj/   # Generated Xcode project
├── project.yml                  # XcodeGen project specification
└── README.md
```

## File Breakdown

### `GoUsageApp.swift`
- **`AppDelegate`**: Owns the `NSStatusItem`, `NSPopover`, hidden `WKWebView`, and the `UsageScraper`. Implements `WKNavigationDelegate` to handle page load completion and auth redirects. Manages the refresh timer and scrape retry loop.
- **`GoUsageApp`**: The `@main` SwiftUI `App` struct that bridges to `AppDelegate` via `@NSApplicationDelegateAdaptor`.

### `MenuBarDropdown.swift`
- **`MenuBarDropdown`**: The main SwiftUI view shown in the popover. Conditionally renders: auth web view, sign-in prompt, loading state, usage meters, or empty state.
- **`UsageRow`**: Renders a single usage meter with label, percentage, colored progress bar, and reset time.
- **`AuthWebViewContainer`**: `NSViewRepresentable` wrapper that embeds the `WKWebView` into SwiftUI for the auth flow.

### `UsageScraper.swift`
- **`UsageScraper`**: `ObservableObject` that publishes `meters`, `isLoggedIn`, `isLoading`, `lastUpdated`, and `isRefreshing`. Contains the JS scraper string, handles `UserDefaults` caching, and manages cookie clearing for sign-out.

### `UsageMeter.swift`
- **`UsageMeter`**: Simple `Identifiable` struct with `label`, `percentage`, `resetTime`, and computed `shortLabel`/`displayLine` properties.

## Key Design Decisions

### Why a hidden WKWebView?
OpenCode GO uses cookie-based authentication. Rather than reimplementing auth, the app loads the real workspace page in a hidden web view that shares cookies with the system browser. This way, if the user is already logged in to OpenCode in Safari/Chrome, the hidden web view picks up the session automatically.

### Why JS scraping?
The OpenCode GO workspace page is a server-rendered web app. The usage data lives in the DOM with semantic `data-slot` attributes, making it reliable to scrape with `document.querySelectorAll`. No API key or OAuth flow needed.

### Why sandbox disabled?
The app needs access to shared `WKWebsiteDataStore` cookies for authentication. App Sandbox would isolate the cookie store, breaking the auth flow.

### Why XcodeGen?
The `project.yml` file keeps the project configuration in a single readable file, avoiding merge conflicts on `.pbxproj` files and making it easy to regenerate the Xcode project.

## Installation

### Download

1. Download `OpencodeGoUsage-v0.1.zip` from [Releases](https://github.com/ashcdev-hub/opencode-go-usage/releases)
2. Unzip and move `Opencode Go Usage.app` to your Applications folder

### Gatekeeper (Unsigned App)

The app is self-signed, so macOS Gatekeeper will block it on first launch. You have two options:

**Option A — Remove quarantine flag (simplest):**

```bash
xattr -d com.apple.quarantine /Applications/Opencode\ Go\ Usage.app
```

**Option B — Bypass via System Settings:**

1. Right-click `Opencode Go Usage.app` → select **Open**
2. When the security warning appears, click **Open**
3. Alternatively: go to **System Settings → Privacy & Security** → click **Open Anyway** next to the blocked app message

The app runs as a menu bar agent (no Dock icon). After launch, look for the GO icon in your menu bar.

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

### Changing the Workspace

Edit the workspace ID in `UsageScraper.swift`:

```swift
static let workspaceID = "wrk_01KMCT31YP92BXJKJZ453HCNSY"
```

### Adjusting Refresh Interval

Change the timer interval in `GoUsageApp.swift`:

```swift
refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { ... }
```

Value is in seconds (300 = 5 minutes).

### Adjusting Scrape Timing

- `scrapeDelay`: Initial delay before first scrape attempt after page load (default: 4 seconds)
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
