import SwiftUI
import WebKit
import Combine

final class AuthState: ObservableObject {
    @Published var isAuthInProgress: Bool = false
    @Published var authWebView: WKWebView? = nil
}

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var scrapeWebView: WKWebView?
    private var authWebView: WKWebView?
    private var hiddenWebViewWindow: NSWindow?
    private var refreshTimer: Timer?
    private var pendingScrapeWork: DispatchWorkItem?
    private var loadGeneration: Int = 0
    private var scrapeRetries = 0
    private let maxScrapeRetries = 3
    private let scrapeDelay: TimeInterval = 4.0
    private let scrapeTeardownDelay: TimeInterval = 5.0
    private let authTeardownDelay: TimeInterval = 5.0
    private var hasRedirectedToWorkspace = false
    private var isManualRefresh = false
    private var aboutWindow: NSWindow?

    private let scraper = UsageScraper()
    private let authState = AuthState()

    private static let passkeyBlocker = """
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupHiddenWindow()
        scraper.loadCachedMeters()
        startRefreshTimer()
        loadWorkspace()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.title = "GO "
        button.image = makeHorizontalBarsImage()
        button.imagePosition = .imageTrailing
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "OpenCode GO Usage"
    }

    private func makeHorizontalBarsImage() -> NSImage {
        let size = NSSize(width: 16, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.controlTextColor.setFill()

        let barX: CGFloat = 0
        let barWidths: [CGFloat] = [6, 10, 14]
        let barHeight: CGFloat = 2.5
        let spacing: CGFloat = 1.5
        let startY: CGFloat = 1

        for (i, w) in barWidths.enumerated() {
            let y = startY + CGFloat(i) * (barHeight + spacing)
            let rect = NSRect(x: barX, y: y, width: w, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            path.fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func setupPopover() {
        popover?.close()
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: MenuBarDropdown(
                scraper: scraper,
                authState: authState,
                onSignIn: { [weak self] in self?.startAuth() },
                onCancelAuth: { [weak self] in self?.cancelAuth() },
                onRefresh: { [weak self] in self?.performRefresh() }
            )
        )
    }

    private func setupHiddenWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderOut(nil)
        hiddenWebViewWindow = window
    }

    // MARK: - WebView Management

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.addUserScript(
            WKUserScript(
                source: AppDelegate.passkeyBlocker,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        return wv
    }

    private func ensureScrapeWebView() -> WKWebView {
        if let wv = scrapeWebView { return wv }
        let wv = makeWebView()
        scrapeWebView = wv
        hiddenWebViewWindow?.contentView = wv
        return wv
    }

    private func teardownScrapeWebView() {
        guard let wv = scrapeWebView else { return }
        wv.stopLoading()
        wv.navigationDelegate = nil
        hiddenWebViewWindow?.contentView = nil
        scrapeWebView = nil
    }

    private func scheduleScrapeTeardown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + scrapeTeardownDelay) { [weak self] in
            guard let self else { return }
            guard !self.popover.isShown else { return }
            guard !self.authState.isAuthInProgress else { return }
            guard self.scrapeRetries == 0 else { return }
            guard self.scraper.meters.count > 0 else { return }
            self.teardownScrapeWebView()
        }
    }

    private func teardownAuthWebView() {
        guard let wv = authWebView else { return }
        wv.stopLoading()
        wv.navigationDelegate = nil
        authWebView = nil
    }

    private func scheduleAuthTeardown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + authTeardownDelay) { [weak self] in
            self?.teardownAuthWebView()
        }
    }

    // MARK: - Loading

    func loadWorkspace() {
        loadGeneration &+= 1
        hasRedirectedToWorkspace = false
        scrapeRetries = 0
        pendingScrapeWork?.cancel()
        pendingScrapeWork = nil
        scraper.isLoading = true
        let wv = ensureScrapeWebView()
        wv.stopLoading()
        let request = URLRequest(url: UsageScraper.workspaceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        wv.load(request)
    }

    func performRefresh() {
        if authState.isAuthInProgress { return }
        if let urlString = scrapeWebView?.url?.absoluteString, isAuthPage(urlString) {
            scraper.isRefreshing = false
            scraper.isLoading = false
            scraper.isLoggedIn = false
            return
        }
        scraper.isRefreshing = true
        isManualRefresh = true
        loadWorkspace()
    }

    func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.authState.isAuthInProgress { return }
            if !self.scraper.isLoggedIn { return }
            if self.scrapeRetries > 0 { return }
            if let last = self.scraper.lastUpdated, Date().timeIntervalSince(last) < 60 { return }
            self.loadWorkspace()
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? ""
        if webView === authWebView {
            handleAuthNavigation(urlString: urlString)
        } else {
            handleScrapeNavigation(urlString: urlString)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("=== load failed: \(error.localizedDescription)")
        if webView === authWebView { return }
        scraper.isLoading = false
        scraper.isRefreshing = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("=== provisional load failed: \(error.localizedDescription)")
        if webView === authWebView { return }
        scraper.isLoading = false
        scraper.isRefreshing = false
    }

    private func handleAuthNavigation(urlString: String) {
        if isOnWorkspace(urlString) {
            handleAuthCompleted()
        }
    }

    private func handleScrapeNavigation(urlString: String) {
        if isOnWorkspace(urlString) {
            scrapeRetries = 0
            if isManualRefresh {
                isManualRefresh = false
                attemptScrape()
            } else {
                scheduleScrapeAttempt(after: scrapeDelay)
            }
        } else if isAuthPage(urlString) {
            scraper.isLoggedIn = false
            scraper.isLoading = false
            scraper.isRefreshing = false
        } else if !hasRedirectedToWorkspace {
            hasRedirectedToWorkspace = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.loadWorkspace()
            }
        }
    }

    private func isOnWorkspace(_ urlString: String) -> Bool {
        urlString.contains(UsageScraper.workspaceID) && !isAuthPage(urlString)
    }

    private func isAuthPage(_ urlString: String) -> Bool {
        urlString.contains("opencode.ai/auth") ||
        urlString.contains("/authorize") ||
        urlString.contains("github.com/login") ||
        urlString.contains("google.com") ||
        urlString.contains("google.co.") ||
        urlString.contains("github.com/login/oauth")
    }

    private func scheduleScrapeAttempt(after delay: TimeInterval) {
        pendingScrapeWork?.cancel()
        let gen = loadGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.loadGeneration == gen else { return }
            self.attemptScrape()
        }
        pendingScrapeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func attemptScrape() {
        guard let wv = scrapeWebView else {
            scraper.isLoading = false
            scraper.isRefreshing = false
            return
        }
        if let urlString = wv.url?.absoluteString, isAuthPage(urlString) {
            scraper.isLoading = false
            scraper.isRefreshing = false
            scraper.isLoggedIn = false
            return
        }
        guard scrapeRetries < maxScrapeRetries else {
            scraper.isLoading = false
            scraper.isRefreshing = false
            return
        }
        scrapeRetries += 1
        let delay = min(1.0 + Double(scrapeRetries) * 0.5, 3.0)

        scraper.scrapeUsage(on: wv) { [weak self] success in
            guard let self else { return }
            if success {
                self.scraper.isLoading = false
                self.scraper.isRefreshing = false
                self.scheduleScrapeTeardown()
            } else {
                self.scheduleScrapeAttempt(after: delay)
            }
        }
    }

    // MARK: - Auth

    func startAuth() {
        guard !authState.isAuthInProgress else { return }
        authState.isAuthInProgress = true
        scraper.isLoading = true
        scraper.isLoggedIn = true

        if authWebView == nil {
            authWebView = makeWebView()
        }
        authState.authWebView = authWebView

        if !popover.isShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        let request = URLRequest(url: UsageScraper.workspaceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        authWebView?.load(request)
    }

    func cancelAuth() {
        authWebView?.stopLoading()
        authState.isAuthInProgress = false
        authState.authWebView = nil
        scraper.isLoggedIn = false
        scraper.isLoading = false
        scheduleAuthTeardown()
    }

    private func handleAuthCompleted() {
        authState.isAuthInProgress = false
        authState.authWebView = nil
        scheduleAuthTeardown()
        scraper.isLoading = true
        isManualRefresh = true
        loadWorkspace()
    }

    // MARK: - Popover

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
        } else {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            }
        }
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(title: "About OpenCode GO Usage", action: #selector(showAboutWindow), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let signOutItem = NSMenuItem(title: "Sign Out", action: #selector(signOut), keyEquivalent: "")
        signOutItem.target = self
        menu.addItem(signOutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - About Window

    @objc func showAboutWindow() {
        if let window = aboutWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About OpenCode GO Usage"
        window.isReleasedWhenClosed = false
        window.center()

        let contentView = NSView(frame: window.contentView!.bounds)

        let titleField = NSTextField(labelWithString: "OpenCode GO Usage")
        titleField.font = .boldSystemFont(ofSize: 16)
        titleField.alignment = .center
        titleField.frame = NSRect(x: 20, y: 150, width: 280, height: 24)
        contentView.addSubview(titleField)

        let copyrightField = NSTextField(labelWithString: "© 2026 Ash Eskrett")
        copyrightField.font = .systemFont(ofSize: 12)
        copyrightField.textColor = .secondaryLabelColor
        copyrightField.alignment = .center
        copyrightField.frame = NSRect(x: 20, y: 125, width: 280, height: 18)
        contentView.addSubview(copyrightField)

        let licenseField = NSTextField(labelWithString: "Licensed under the MIT License.\nSee LICENSE for details.")
        licenseField.font = .systemFont(ofSize: 11)
        licenseField.textColor = .tertiaryLabelColor
        licenseField.alignment = .center
        licenseField.frame = NSRect(x: 20, y: 95, width: 280, height: 28)
        contentView.addSubview(licenseField)

        let linkField = NSTextField(labelWithString: "github.com/ashcdev-hub/opencode-go-usage")
        linkField.font = .systemFont(ofSize: 11)
        linkField.textColor = .controlAccentColor
        linkField.alignment = .center
        linkField.isSelectable = true
        linkField.frame = NSRect(x: 20, y: 65, width: 280, height: 18)
        let linkGesture = NSClickGestureRecognizer(target: self, action: #selector(openGitHubLink))
        linkField.addGestureRecognizer(linkGesture)
        contentView.addSubview(linkField)

        window.contentView = contentView
        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openGitHubLink() {
        if let url = URL(string: "https://github.com/ashcdev-hub/opencode-go-usage") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Sign Out

    @objc private func signOut() {
        scraper.clearCookies()
        loadWorkspace()
    }
}

@main
struct GoUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}
