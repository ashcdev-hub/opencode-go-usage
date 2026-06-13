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

    func scrapeUsage(on webView: WKWebView, completion: ((Bool) -> Void)? = nil) {
        webView.evaluateJavaScript(UsageScraper.scraperJS) { [weak self] result, error in
            guard error == nil,
                  let jsonString = result as? String,
                  !jsonString.isEmpty,
                  let data = jsonString.data(using: .utf8),
                  let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !items.isEmpty else {
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
                completion?(false)
                return
            }

            DispatchQueue.main.async {
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
