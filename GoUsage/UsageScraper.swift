import Foundation
import WebKit
import Combine

class UsageScraper: ObservableObject {
    @Published var meters: [UsageMeter] = []
    @Published var isLoggedIn = false
    @Published var isLoading = true
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false

    static let workspaceID = "wrk_01KMCT31YP92BXJKJZ453HCNSY"
    static let workspaceURL = URL(string: "https://opencode.ai/workspace/\(workspaceID)/go")!

    static let scraperJS = """
    (function() {
        var items = document.querySelectorAll('div[data-slot="usage-preview-item"]');
        if (!items || items.length === 0) {
            items = document.querySelectorAll('div[data-slot="usage-item"]');
        }
        if (!items || items.length === 0) return null;

        var results = [];
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            var labelEl = item.querySelector('span[data-slot="usage-preview-label"]') ||
                          item.querySelector('span[data-slot="usage-label"]');
            var valueEl = item.querySelector('span[data-slot="usage-preview-value"]') ||
                          item.querySelector('span[data-slot="usage-value"]');
            var resetEl = item.querySelector('span[data-slot="usage-preview-reset"]') ||
                          item.querySelector('span[data-slot="reset-time"]');
            if (!labelEl || !valueEl || !resetEl) continue;

            var label = (labelEl.innerText || '').trim();
            var valueText = (valueEl.innerText || '').trim();
            var match = valueText.match(/(\\d+)%/);
            var percentage = match ? parseInt(match[1], 10) : -1;
            var resetTime = (resetEl.innerText || '').trim();

            if (label.length === 0 || percentage < 0 || resetTime.length === 0) continue;

            results.push({ label: label, percentage: percentage, resetTime: resetTime });
        }

        if (results.length === 0) return null;
        return JSON.stringify(results);
    })()
    """

    static let diagnosticJS = """
    (function() {
        var info = {};
        info.url = window.location.href;
        info.title = document.title;
        info.bodyLength = document.body ? document.body.innerHTML.length : 0;

        var slots = [];
        document.querySelectorAll('[data-slot]').forEach(function(el) {
            slots.push(el.tagName + '[data-slot="' + el.getAttribute('data-slot') + '"]:' + (el.innerText || '').substring(0, 60));
        });
        info.dataSlots = slots.slice(0, 50);

        var pcts = [];
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (walker.nextNode()) {
            var txt = walker.currentNode.textContent.trim();
            if (txt.indexOf('%') !== -1 && txt.length < 80) {
                var parent = walker.currentNode.parentElement;
                var tag = parent ? parent.tagName + '.' + (parent.className || '').substring(0, 40) : '?';
                pcts.push(tag + ' => "' + txt + '"');
            }
        }
        info.pctTexts = pcts.slice(0, 30);

        var progress = [];
        document.querySelectorAll('[role="progressbar"], [aria-valuenow], progress').forEach(function(el) {
            progress.push(el.tagName + ' aria-valuenow=' + el.getAttribute('aria-valuenow') + ' class=' + (el.className || '').substring(0, 50));
        });
        info.progressBars = progress.slice(0, 20);

        var bodyChildren = [];
        if (document.body) {
            for (var i = 0; i < Math.min(document.body.children.length, 15); i++) {
                var c = document.body.children[i];
                bodyChildren.push(c.tagName + '#' + c.id + ' class=' + (c.className || '').substring(0, 60) + ' children=' + c.children.length);
            }
        }
        info.bodyChildren = bodyChildren;

        var main = document.querySelector('#__next') || document.querySelector('#root') || document.querySelector('#app') || document.querySelector('main');
        if (main) {
            var sub = [];
            for (var j = 0; j < Math.min(main.children.length, 20); j++) {
                var s = main.children[j];
                sub.push(s.tagName + '#' + s.id + ' class=' + (s.className || '').substring(0, 60));
            }
            info.mainChildren = sub;
            info.mainTag = main.tagName + '#' + main.id;
            info.mainHTML = main.innerHTML.substring(0, 2000);
        }

        return JSON.stringify(info, null, 2);
    })()
    """

    func dumpPageStructure(on webView: WKWebView) {
        webView.evaluateJavaScript(UsageScraper.diagnosticJS) { result, error in
            if let error = error {
                print("=== DIAGNOSTIC: error: \(error.localizedDescription)")
                return
            }
            if let str = result as? String {
                print("=== DIAGNOSTIC START ===")
                print(str)
                print("=== DIAGNOSTIC END ===")
            } else {
                print("=== DIAGNOSTIC: unexpected result type: \(type(of: result))")
            }
        }
    }

    func scrapeUsage(on webView: WKWebView, completion: ((Bool) -> Void)? = nil) {
        webView.evaluateJavaScript(UsageScraper.scraperJS) { [weak self] result, error in
            print("=== scrapeUsage: JS returned: \(result ?? "nil"), error: \(error?.localizedDescription ?? "none")")

            guard error == nil,
                  let jsonString = result as? String,
                  !jsonString.isEmpty,
                  let data = jsonString.data(using: .utf8),
                  let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !items.isEmpty else {
                print("=== scrapeUsage: no valid items found")
                completion?(false)
                return
            }

            let meters = items.map { item in
                UsageMeter(
                    label: item["label"] as? String ?? "",
                    percentage: item["percentage"] as? Int ?? 0,
                    resetTime: item["resetTime"] as? String ?? ""
                )
            }

            let hasRealData = meters.contains { !$0.label.isEmpty && $0.percentage >= 0 && !$0.resetTime.isEmpty }
            guard hasRealData else {
                print("=== scrapeUsage: items found but all empty")
                completion?(false)
                return
            }

            DispatchQueue.main.async {
                print("=== scrapeUsage: parsed \(meters.count) meters with real data")
                self?.meters = meters
                self?.isLoggedIn = true
                self?.isLoading = false
                self?.lastUpdated = Date()
                self?.saveCachedMeters(meters)
                completion?(true)
            }
        }
    }

    private func saveCachedMeters(_ meters: [UsageMeter]) {
        let data = meters.map { ["label": $0.label, "percentage": $0.percentage, "resetTime": $0.resetTime] as [String: Any] }
        UserDefaults.standard.set(data, forKey: "cachedMeters")
        UserDefaults.standard.set(Date(), forKey: "lastUpdated")
    }

    func loadCachedMeters() {
        if let data = UserDefaults.standard.array(forKey: "cachedMeters") as? [[String: Any]],
           !data.isEmpty {
            meters = data.map { item in
                UsageMeter(
                    label: item["label"] as? String ?? "",
                    percentage: item["percentage"] as? Int ?? 0,
                    resetTime: item["resetTime"] as? String ?? ""
                )
            }
            isLoggedIn = true
            isLoading = false
        }
        lastUpdated = UserDefaults.standard.object(forKey: "lastUpdated") as? Date
    }

    func hasValidSession() -> Bool {
        return isLoggedIn && !meters.isEmpty
    }

    func clearCookies() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                if let cookies = HTTPCookieStorage.shared.cookies {
                    for cookie in cookies {
                        HTTPCookieStorage.shared.deleteCookie(cookie)
                    }
                }
                DispatchQueue.main.async {
                    self.meters = []
                    self.isLoggedIn = false
                    self.isLoading = false
                    self.lastUpdated = nil
                    UserDefaults.standard.removeObject(forKey: "cachedMeters")
                    UserDefaults.standard.removeObject(forKey: "lastUpdated")
                }
            }
        }
    }
}
