import SwiftUI
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var webView: WKWebView!
    private var hiddenWebViewWindow: NSWindow?
    private var refreshTimer: Timer?
    private var scrapeRetries = 0
    private let maxScrapeRetries = 20
    private let scrapeDelay: TimeInterval = 4.0
    private var hasRedirectedToWorkspace = false
    private var isAuthInProgress = false

    let scraper = UsageScraper()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("=== GoUsage: launching ===")
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()

        setupWebView()
        setupHiddenWebViewWindow()
        scraper.loadCachedMeters()
        loadWorkspace()
        startRefreshTimer()

        print("=== GoUsage: status item created ===")
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.title = "GO "

        if let img = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "GO Usage") {
            button.image = img
        } else {
            button.image = makeFallbackImage()
        }

        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.toolTip = "OpenCode GO Usage"

        print("Button title: \(button.title), frame: \(button.frame)")
    }

    private func makeFallbackImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        let path = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 14, height: 14))
        NSColor.controlTextColor.setFill()
        path.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func setupPopover() {
        popover?.close()
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 200)
        popover.behavior = .transient
        popover.animates = true
        updatePopoverContent()
    }

    private func updatePopoverContent() {
        popover.contentViewController = NSHostingController(
            rootView: MenuBarDropdown(
                scraper: scraper,
                webView: isAuthInProgress ? webView : nil,
                onSignIn: { [weak self] in self?.startAuth() },
                onCancelAuth: { [weak self] in self?.cancelAuth() },
                onRefresh: { [weak self] in self?.performRefresh() }
            )
        )
    }

    private func refreshPopover() {
        guard let button = statusItem.button else { return }
        updatePopoverContent()
        if popover.isShown {
            popover.close()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - WKWebView

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let passkeyBlocker = """
        (function() {
            try {
                Object.defineProperty(window.navigator, 'credentials', {
                    get: function() {
                        return {
                            get: function() { return Promise.reject(new Error('not supported')); },
                            create: function() { return Promise.reject(new Error('not supported')); },
                            store: function() { return Promise.reject(new Error('not supported')); },
                            preventSilentAccess: function() { return Promise.resolve(); }
                        };
                    },
                    configurable: true
                });
                if (window.PublicKeyCredential) {
                    window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = function() { return Promise.resolve(false); };
                    window.PublicKeyCredential.isConditionalMediationAvailable = function() { return Promise.resolve(false); };
                }
            } catch(e) {}
        })();
        """
        let script = WKUserScript(source: passkeyBlocker, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 700), configuration: config)
        webView.navigationDelegate = self
        print("=== WKWebView created ===")
    }

    private func setupHiddenWebViewWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderOut(nil)
        hiddenWebViewWindow = window
        print("=== Hidden webView window created ===")
    }

    func loadWorkspace() {
        guard webView != nil else {
            print("=== loadWorkspace: webView nil, retrying in 0.5s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.loadWorkspace() }
            return
        }
        print("=== Loading workspace URL: \(UsageScraper.workspaceURL.absoluteString)")
        hasRedirectedToWorkspace = false
        scrapeRetries = 0
        scraper.isLoading = true
        webView.stopLoading()
        let request = URLRequest(url: UsageScraper.workspaceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        webView.load(request)
    }

    func performRefresh() {
        guard webView != nil else {
            scraper.isRefreshing = false
            scraper.isLoading = false
            return
        }
        if isAuthInProgress {
            print("=== Manual refresh: auth in progress, ignoring")
            scraper.isRefreshing = false
            return
        }
        if let urlString = webView?.url?.absoluteString, isAuthPage(urlString) {
            print("=== Manual refresh: on auth page — login required")
            scraper.isRefreshing = false
            scraper.isLoading = false
            scraper.isLoggedIn = false
            refreshPopover()
            return
        }
        print("=== Manual refresh: full reload")
        scraper.isRefreshing = true
        scraper.isLoading = true
        loadWorkspace()
    }

    func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            print("=== Refresh timer fired")
            self?.loadWorkspace()
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? ""
        print("=== didFinish: \(urlString)")

        if isAuthInProgress {
            if isOnWorkspace(urlString) {
                handleAuthCompleted()
                return
            } else if isAuthPage(urlString) {
                print("=== Auth page detected — user can authenticate")
                return
            }
        }

        if isOnWorkspace(urlString) {
            print("=== Workspace page detected, scraping in \(Int(scrapeDelay))s...")
            scrapeRetries = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + scrapeDelay) { [weak self] in
                self?.attemptScrape()
            }
        } else if isAuthPage(urlString) {
            print("=== Auth page detected")
            DispatchQueue.main.async { [weak self] in
                self?.scraper.isLoggedIn = false
                self?.scraper.isLoading = false
                self?.scraper.isRefreshing = false
                self?.refreshPopover()
            }
        } else if !hasRedirectedToWorkspace {
            print("=== Non-workspace page detected, redirecting to workspace...")
            hasRedirectedToWorkspace = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.loadWorkspace()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("=== didFail: \(error.localizedDescription)")
        scraper.isLoading = false
        scraper.isRefreshing = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("=== didFailProvisional: \(error.localizedDescription)")
        scraper.isLoading = false
         scraper.isRefreshing = false
    }

    private func isOnWorkspace(_ urlString: String) -> Bool {
        urlString.contains(UsageScraper.workspaceID) && !isAuthPage(urlString)
    }

    private func isAuthPage(_ urlString: String) -> Bool {
        return urlString.contains("opencode.ai/auth") ||
               urlString.contains("/authorize") ||
               urlString.contains("github.com/login") ||
               urlString.contains("google.com") ||
               urlString.contains("google.co.") ||
               urlString.contains("github.com/login/oauth")
    }

    private func attemptScrape() {
        if let urlString = webView?.url?.absoluteString, isAuthPage(urlString) {
            print("=== scrape: on auth page, skipping — login required")
            DispatchQueue.main.async { [weak self] in
                self?.scraper.isLoading = false
                self?.scraper.isRefreshing = false
                self?.scraper.isLoggedIn = false
                self?.refreshPopover()
            }
            return
        }
        guard scrapeRetries < maxScrapeRetries else {
            print("=== scrape: exhausted retries, giving up")
            DispatchQueue.main.async { [weak self] in
                self?.scraper.isLoading = false
                self?.scraper.isRefreshing = false
            }
            return
        }
        scrapeRetries += 1
        if scrapeRetries == 1 {
            scraper.dumpPageStructure(on: webView)
        }
        let delay = min(1.0 + Double(scrapeRetries) * 0.5, 3.0)
        print("=== scrape attempt \(scrapeRetries)/\(maxScrapeRetries) (retry interval: \(String(format: "%.1f", delay))s)")

        scraper.scrapeUsage(on: webView) { [weak self] success in
            if success {
                print("=== scrape: success!")
                DispatchQueue.main.async { [weak self] in
                    self?.scraper.isLoading = false
                    self?.scraper.isRefreshing = false
                    self?.refreshPopover()
                }
            } else {
                print("=== scrape: no valid data yet, retrying in \(String(format: "%.1f", delay))s...")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self?.attemptScrape()
                }
            }
        }
    }

    // MARK: - Auth

    func startAuth() {
        guard !isAuthInProgress else {
            print("=== auth already in progress")
            return
        }
        print("=== startAuth called")
        isAuthInProgress = true

        hiddenWebViewWindow?.contentView = nil

        scraper.isLoggedIn = false
        scraper.isLoading = false
        refreshPopover()

        if !popover.isShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        let request = URLRequest(url: UsageScraper.workspaceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        webView.load(request)
    }

    func cancelAuth() {
        print("=== cancelAuth called")
        webView.stopLoading()
        isAuthInProgress = false
        hiddenWebViewWindow?.contentView = webView
        scraper.isLoggedIn = false
        scraper.isLoading = false
        refreshPopover()
    }

    private func handleAuthCompleted() {
        print("=== Auth completed — workspace detected")
        isAuthInProgress = false
        hiddenWebViewWindow?.contentView = webView

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.scraper.isLoading = true
            self?.refreshPopover()
            self?.loadWorkspace()
        }
    }

    // MARK: - Popover

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
                if let monitor = self?.eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    self?.eventMonitor = nil
                }
            }
        }
    }
}

@main
struct GoUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}
