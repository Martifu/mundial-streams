import SwiftUI
@preconcurrency import WebKit

struct WebStreamView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        load(url, in: webView, coordinator: context.coordinator, reloadToken: reloadToken)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentURL != url || context.coordinator.reloadToken != reloadToken else {
            return
        }
        load(url, in: webView, coordinator: context.coordinator, reloadToken: reloadToken)
    }

    private func load(_ url: URL, in webView: WKWebView, coordinator: Coordinator, reloadToken: Int) {
        coordinator.currentURL = url
        coordinator.reloadToken = reloadToken

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let origin = sourceOrigin(for: url)
        request.setValue(origin.referer, forHTTPHeaderField: "Referer")
        request.setValue(origin.origin, forHTTPHeaderField: "Origin")
        webView.load(request)
    }

    private func sourceOrigin(for url: URL) -> (referer: String, origin: String) {
        let host = url.host()?.lowercased() ?? ""
        if host.contains("findleembeds")
            || host.contains("xyzstreams")
            || host.contains("junkieembeds")
            || host.contains("timstreams")
            || host.contains("luluvid")
            || host.contains("vimeo") {
            return ("https://timstreams.net/", "https://timstreams.net")
        }
        return ("https://crckstreams.ch/", "https://crckstreams.ch")
    }

    final class Coordinator {
        var currentURL: URL?
        var reloadToken = 0
    }
}
