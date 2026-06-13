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

## How It Works

The app uses two `WKWebView`s that share the same `WKWebsiteDataStore.default()` cookie jar:

- A **scrape webview** that lives in a hidden offscreen window, used to load the workspace page and scrape usage data
- An **auth webview** that is created on demand when the user signs in, and is destroyed when the auth flow ends

After the scrape page loads, JavaScript is injected to scrape the usage data from the DOM. The scraped data (labels, percentages, reset times) is parsed and displayed in a SwiftUI popover attached to the menu bar status item.

### Architecture

```
┌─────────────────────────────────────────────┐
│  NSStatusItem (menu bar "GO" button)        │
│  ├── Left-click → NSPopover                 │
│  │   └── NSHostingController (created once) │
│  │       └── MenuBarDropdown (SwiftUI)      │
│  │           ├── Auth / Loading / Empty     │
│  │           ├── Usage (Rolling/Wk/Mo)      │
│  │           └── Footer (refresh/quit)      │
│  └── Right-click → NSMenu                   │
│      ├── About OpenCode GO Usage            │
│      ├── Sign Out                           │
│      └── Quit                               │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Hidden NSWindow (offscreen)                │
│  └── Scrape WKWebView (lazy, torn down idle)│
│      └── Loads opencode.ai/workspace/go     │
│      └── JS scraper + MutationObserver      │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Auth WKWebView (created on demand)         │
│  └── Shown inside popover during sign-in    │
│  └── Destroyed when auth flow ends          │
└─────────────────────────────────────────────┘
```

### Data Flow

1. **Launch** → cached usage is displayed immediately from `UserDefaults`
2. **Hidden scrape webview** is created lazily, loads the workspace URL, and authenticates via shared cookies
3. **`didFinish` delegate** fires after page load → 4 second delay → scrape attempts begin
4. **JS scraper** (`UsageScraper.scraperJS`) first tries to read `data-slot="usage-preview-item"` elements; if the DOM is not yet rendered, it sets up a `MutationObserver` that resolves as soon as the data appears (3 s timeout fallback)
5. **Parsed data** updates `@Published meters` → SwiftUI re-renders the popover
6. **5 seconds after a successful scrape**, if the popover is closed and the user is not in an auth flow, the scrape webview is torn down (cookies persist in `WKWebsiteDataStore`)
7. **Auto-refresh timer** re-creates the scrape webview and re-runs `loadWorkspace()` every 5 minutes — gated to skip when logged out, mid-scrape, or less than 60 s since the last success

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

## File Breakdown

### `GoUsageApp.swift`
- **`AuthState`** (`ObservableObject`): two `@Published` fields — `isAuthInProgress` and `authWebView`. Drives the popover's auth branch via SwiftUI observation (no manual popover refresh).
- **`AppDelegate`**: Owns the `NSStatusItem`, `NSPopover`, the hidden `NSWindow`, the two `WKWebView`s, and the `UsageScraper`. Implements `WKNavigationDelegate` to handle page load completion and auth redirects. Manages the refresh timer, scrape retry chain, and webview teardown. The hosting controller is created once; the popover content is updated purely through `@ObservedObject` invalidation.
- **Right-click context menu**: Left-click toggles the usage popover; right-click shows an `NSMenu` with About, Sign Out, and Quit.
- **About window**: `showAboutWindow()` creates a centered `NSWindow` with app name, copyright (© 2026 Ash Eskrett), MIT license notice, and a clickable link to the GitHub repo.

### `MenuBarDropdown.swift`
- **`MenuBarDropdown`**: The main SwiftUI view shown in the popover. Conditionally renders: auth web view, sign-in prompt, loading state, usage meters, or empty state.
- **`UsageRow`**: Renders a single usage meter with label, percentage, colored progress bar, and reset time.
- **`AuthWebViewContainer`**: `NSViewRepresentable` wrapper that embeds the `WKWebView` into SwiftUI for the auth flow.
- **`RelativeUpdatedText`**: Tiny subview that isolates the auto-invalidating relative-time text from the rest of the popover body.

### `UsageScraper.swift`
- **`UsageScraper`**: `ObservableObject` that publishes `meters`, `isLoggedIn`, `isLoading`, `lastUpdated`, and `isRefreshing`. Contains the JS scraper string (with `MutationObserver` fallback for not-yet-rendered pages), handles `UserDefaults` caching, and manages cookie clearing for sign-out.

### `UsageMeter.swift`
- **`UsageMeter`**: Simple `Identifiable` struct with `label`, `percentage`, `resetTime`, and a computed `shortLabel`. The `id` is derived from `label` (stable across scrapes) so SwiftUI's `ForEach` diffing preserves the implicit percentage animation.

## Key Design Decisions

### Why two WKWebViews (scrape + auth)?
The single-webview design had to constantly reparent the view between the hidden window and the popover, which is fragile and risked an autoresizing issue. The two-webview design lets the scrape webview live in its hidden window with a fixed frame, and the auth webview be created/destroyed on demand for the sign-in flow. Both webviews share `WKWebsiteDataStore.default()`, so cookies (and therefore the session) are shared.

### Why a hidden WKWebView?
OpenCode GO uses cookie-based authentication. Rather than reimplementing auth, the app loads the real workspace page in a hidden web view that shares cookies with Safari. This way, if the user is already logged in to OpenCode in Safari, the hidden web view picks up the session automatically.

### Why tear down the webview when idle?
A live `WKWebView` keeps a full WebContent process resident (≈40-80 MB RSS, plus its render tree, JS engine, and timers in the loaded page). For a menu bar app that the user only glances at, that's a lot of permanent cost. The scrape webview is torn down 5 seconds after a successful scrape, gated on the popover being closed and the user not actively authenticating. It is re-created on the next manual refresh or auto-refresh tick. The cost is a 1-2 s WebContent process spinup per refresh — acceptable for a 5-minute interval.

### Why JS scraping?
The OpenCode GO workspace page is a server-rendered web app. The usage data lives in the DOM with semantic `data-slot` attributes, making it reliable to scrape with `document.querySelectorAll`. No API key or OAuth flow needed.

### Why sandbox disabled?
The app needs access to shared `WKWebsiteDataStore` cookies for authentication. App Sandbox would isolate the cookie store, breaking the auth flow.

### Why XcodeGen?
The `project.yml` file keeps the project configuration in a single readable file, avoiding merge conflicts on `.pbxproj` files and making it easy to regenerate the Xcode project.

## Installation

### Download

1. Download the latest [Release](https://github.com/ashcdev-hub/opencode-go-usage/releases)
2. Unzip and move `Opencode Go Usage.app` to your Applications folder
3. On first launch, right-click the app → Open → click Open to bypass Gatekeeper

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
- `maxScrapeRetries`: Maximum number of scrape attempts (default: 3). The scraper JS internally uses a `MutationObserver` with a 3 s timeout, so each attempt waits up to 3 s before resolving.
- Retry backoff: starts at 1.5s, increases by 0.5s each attempt, caps at 3.0s

### Adjusting Idle Teardown

In `GoUsageApp.swift`:

- `scrapeTeardownDelay` (default: 5 s): how long to wait after a successful scrape before tearing down the hidden scrape webview
- `authTeardownDelay` (default: 5 s): how long to wait after auth completes or is cancelled before tearing down the auth webview

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
