import AppKit
import Darwin
import SwiftUI
import WebKit

/// Native hardware scanning with a locally bundled, editable web interface.
@MainActor
struct OrbitWebView: NSViewRepresentable {
    @ObservedObject var model: MapModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "portMap")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        if let entry = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Orbit") {
            context.coordinator.entry = entry
            webView.loadFileURL(entry, allowingReadAccessTo: entry.deletingLastPathComponent())
        } else {
            webView.navigationDelegate = nil
            webView.loadHTMLString("<h1>Port Map</h1><p>The Orbit interface is missing. Rebuild with ./build.sh.</p>", baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.publish()
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "portMap")
        view.navigationDelegate = nil
        view.stopLoading()
        coordinator.webView = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let model: MapModel
        weak var webView: WKWebView?
        var entry: URL?
        private var ready = false
        private var lastEvent: Data?
        private var smokeStarted = false

        init(model: MapModel) { self.model = model }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let entry, message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.standardizedFileURL == entry.standardizedFileURL,
                  let body = message.body as? [String: Any],
                  let version = body["schemaVersion"] as? Int, version == 1,
                  let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                lastEvent = nil
                publish()
            case "refresh":
                guard !model.refreshing else { return }
                Task { await model.refresh() }
            case "demo":
                model.orbitDemo = true
                publish()
            case "appearance":
                switch body["value"] as? String {
                case "light": webView?.window?.appearance = NSAppearance(named: .aqua)
                case "dark": webView?.window?.appearance = NSAppearance(named: .darkAqua)
                case "system": webView?.window?.appearance = nil
                default: break
                }
            default: break
            }
        }

        func publish() {
            guard ready, let webView else { return }
            var event: [String: Any] = ["type": "state", "schemaVersion": 1,
                                        "demo": model.orbitDemo, "refreshing": model.refreshing]
            if !model.orbitDemo {
                if let scan = model.scan { event["snapshot"] = orbitSnapshot(scan: scan) }
                if let error = model.error { event["error"] = error }
            }
            guard let data = try? JSONSerialization.data(withJSONObject: event, options: .sortedKeys),
                  data != lastEvent else { return }
            lastEvent = data
            // Structured arguments keep device names and helper errors out of JavaScript source.
            webView.callAsyncJavaScript("window.portMap.receive(event)", arguments: ["event": event],
                                        in: nil, contentWorld: .page) { [weak self] result in
                if case .failure(let error) = result {
                    NSLog("Orbit bridge error: %@", error.localizedDescription)
                } else {
                    self?.runSmokeTestIfNeeded()
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let allowed = entry != nil && action.request.url?.standardizedFileURL == entry?.standardizedFileURL
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false
            lastEvent = nil
            if let entry { webView.loadFileURL(entry, allowingReadAccessTo: entry.deletingLastPathComponent()) }
        }

        private func runSmokeTestIfNeeded() {
            guard CommandLine.arguments.contains("--smoke-test"), !smokeStarted else { return }
            smokeStarted = true
            let port = Port(id: "Port-USB-C@1", position: "@1", group: "Front USB-C",
                            label: "P9227 Slim", connected: true, link: "480 Mb/s", cable: nil,
                            cableMatches: [], connections: [Connection(id: "fixture-drive", name: "P9227 Slim",
                            detail: "LaCie", speed: "480 Mbps", icon: "externaldrive")])
            let fixture: [String: Any] = ["type": "state", "schemaVersion": 1, "refreshing": false,
                                         "snapshot": orbitSnapshot(scan: PortScan(ports: [port], version: "smoke-test", isMacMini: true))]
            webView?.callAsyncJavaScript("""
                if (document.querySelectorAll('.device').length !== 19) throw new Error('Missing demo images');
                document.querySelector('[data-appearance="dark"]').click();
                if (document.body.dataset.variant !== 'afterhours') throw new Error('Dark appearance failed');
                document.querySelector('[data-appearance="light"]').click();
                if (document.body.dataset.variant !== 'clay') throw new Error('Light appearance failed');
                if (!window.portMap) throw new Error('Native bridge missing');
                window.portMap.receive(fixture);
                if (document.querySelectorAll('.device').length !== 2) throw new Error('Native inventory export failed');
                if (!document.querySelector('#devices').textContent.includes('LaCie')) throw new Error('Native device missing');
                return 'Orbit WKWebView smoke test passed: appearances, demo images, and native inventory';
                """, arguments: ["fixture": fixture], in: nil, contentWorld: .page) { result in
                    switch result {
                    case .success(let value):
                        print(value)
                        exit(0)
                    case .failure(let error):
                        NSLog("Orbit smoke test failed: %@", error.localizedDescription)
                        exit(1)
                    }
                }
        }
    }
}
