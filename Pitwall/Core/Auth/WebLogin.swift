#if !os(tvOS)
import Foundation
import WebKit
import Observation

/// Shows the official F1 sign-in page and picks up the finished session from the
/// site's own storage. The password stays inside F1's page; Pitwall never sees it.
@MainActor
@Observable
final class WebLogin: NSObject, WKNavigationDelegate, WKUIDelegate {
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var currentHost: String?

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        // The F1 site serves a simplified page to unknown agents; present as Safari.
        #if os(macOS)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        #else
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        #endif
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// Loads the page and waits until the user has signed in (or the task is cancelled).
    func signIn() async -> F1Session? {
        errorMessage = nil
        webView.load(URLRequest(url: F1Endpoints.loginURL))
        for _ in 0..<900 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return nil }
            if let session = await readSession() {
                webView.stopLoading()
                return session
            }
        }
        errorMessage = String(localized: "Inloggen duurde te lang. Probeer het opnieuw.")
        return nil
    }

    func reload() {
        errorMessage = nil
        webView.load(URLRequest(url: F1Endpoints.loginURL))
    }

    private func readSession() async -> F1Session? {
        // 1. localStorage on account.formula1.com (current site)
        if webView.url?.host == "account.formula1.com",
           let json = try? await webView.evaluateJavaScript("localStorage.getItem('ascSessionInfo')") as? String,
           let session = F1Session.decode(Data(json.utf8)) {
            return session
        }
        // 2. The login-session cookie used by older versions of the site
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        if let cookie = cookies.first(where: { $0.name == "login-session" && $0.domain.hasSuffix("formula1.com") }),
           let decoded = cookie.value.removingPercentEncoding,
           let session = F1Session.decode(Data(decoded.utf8)) {
            return session
        }
        return nil
    }

    func clear() {
        pollTask?.cancel()
        webView.stopLoading()
        webView.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        currentHost = webView.url?.host
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        currentHost = webView.url?.host
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    private func handle(_ error: Error) {
        isLoading = false
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = String(localized: "De inlogpagina kon niet laden. Controleer je verbinding.")
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Open target=_blank links (e.g. social sign-in) in the same view.
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}
#endif
