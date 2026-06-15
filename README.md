# Opencode Go Usage

A lightweight macOS menu bar app that displays your [OpenCode GO](https://opencode.ai/go) subscription usage in real time. No more checking a browser tab to see when your limits reset.

Inspired by needing to quickly view usage stats that I wasn't seeing in [Opencode Stats](https://github.com/fayazara/opencode-stats).

## Features

- **Live usage data** — scrapes your OpenCode GO workspace page to display rolling, weekly, monthly usage percentages with progress bars and time to reset counters.
- **Auto-refresh** — data refreshes automatically every 5 minutes (when logged in and idle)
- **Manual refresh** — click the refresh button for an instant (~1s) data refresh
- **Background operation** — runs as an `LSUIElement` (no Dock icon), purely menu bar–based
- **Session persistence** — caches usage data locally so the popover shows meaningful data immediately on launch while the hidden web view re-authenticates
- **Idle-friendly** — the hidden web view is torn down between scrapes so the app sits at near-baseline memory when you're not looking at it
- **Snappy sign-in** — the popover shows a loading spinner throughout the auth flow and renders progress bars within ~2–3 s of completing sign-in
- **Right-click context menu** — right-click the menu bar icon for About, Sign Out, and Quit

## Requirements

- macOS 14.4+

## Installation

### Download

1. Download the latest [Release](https://github.com/ashcdev-hub/opencode-go-usage/releases)
2. Unzip and move `Opencode Go Usage.app` to your Applications folder
3. When the security warning appears, go to **System Settings → Privacy & Security** → click **Open Anyway** next to the blocked app message

The app is self-signed so macOS Gatekeeper will block it on first launch. Either follow the guidance above or remove the quarantine flag:

```bash
xattr -d com.apple.quarantine /Applications/Opencode\ Go\ Usage.app
```

## License

MIT

## Author

Ash Eskrett
