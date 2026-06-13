import SwiftUI
import WebKit

struct MenuBarDropdown: View {
    @ObservedObject var scraper: UsageScraper
    var webView: WKWebView?
    var onSignIn: () -> Void = {}
    var onCancelAuth: () -> Void = {}
    var onRefresh: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let webView = webView {
                authView(webView: webView)
            } else if scraper.meters.isEmpty && !scraper.isLoggedIn {
                notLoggedInView
            } else if scraper.meters.isEmpty && scraper.isLoading {
                loadingView
            } else if scraper.meters.isEmpty {
                emptyView
            } else {
                usageView
            }

            Divider().padding(.vertical, 4)

            footerView
        }
        .frame(width: 320)
    }

    private var notLoggedInView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.circle")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("Sign in to OpenCode GO")
                .font(.headline)
            Text("Click below to authenticate and view your usage.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Sign In") {
                onSignIn()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private func authView(webView: WKWebView) -> some View {
        VStack(spacing: 8) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Sign in below")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel") {
                    onCancelAuth()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            AuthWebViewContainer(webView: webView)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(8)
    }

    private var loadingView: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text("Loading usage data...")
                .foregroundColor(.secondary)
        }
        .padding(16)
    }

    private var emptyView: some View {
        Text("No usage data available.")
            .foregroundColor(.secondary)
            .padding(16)
    }

    private var usageView: some View {
        VStack(spacing: 0) {
            ForEach(scraper.meters) { meter in
                UsageRow(meter: meter)
            }
        }
    }

    private var footerView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Opencode Go Usage")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.6))
                if let date = scraper.lastUpdated {
                    Text("Updated \(date, style: .relative) ago")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                Button(action: {
                    onRefresh()
                }) {
                    if scraper.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderless)
                .help("Refresh usage data")
                .disabled(scraper.isRefreshing)

                Button(action: {
                    scraper.clearCookies()
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Sign out and clear session")

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Quit Opencode Go Usage")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct AuthWebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct UsageRow: View {
    let meter: UsageMeter

    var percentageColor: Color {
        switch meter.percentage {
        case 0..<50: return .green
        case 50..<75: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(meter.shortLabel)
                .font(.system(.body, design: .monospaced))
                .frame(width: 65, alignment: .leading)

            Text("\(meter.percentage)%")
                .font(.system(.body, design: .monospaced).bold())
                .foregroundColor(percentageColor)
                .frame(width: 42, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(percentageColor)
                        .frame(width: geo.size.width * CGFloat(meter.percentage) / 100)
                        .animation(.easeInOut(duration: 0.5), value: meter.percentage)
                }
            }
            .frame(height: 8)

            Text(meter.resetTime)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 85, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
