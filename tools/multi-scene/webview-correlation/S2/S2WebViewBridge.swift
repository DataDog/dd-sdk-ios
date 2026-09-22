import Foundation
import UIKit
import WebKit
import DatadogWebViewTracking

/// Observes the actual installed SDK handler, forwarding every message once.
@MainActor
final class S2WebViewContentController: WKUserContentController {
    let documentID = UUID().uuidString.lowercased()
    private let evidence: S2WebViewEvidence

    init(evidence: S2WebViewEvidence) {
        self.evidence = evidence
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        guard name == "DatadogEventBridge" else {
            super.add(scriptMessageHandler, name: name)
            return
        }
        super.add(Observer(downstream: scriptMessageHandler, evidence: evidence, documentID: documentID), name: name)
    }

    @MainActor
    private final class Observer: NSObject, WKScriptMessageHandler {
        private let downstream: WKScriptMessageHandler
        private let evidence: S2WebViewEvidence
        private let documentID: String

        init(downstream: WKScriptMessageHandler, evidence: S2WebViewEvidence, documentID: String) {
            self.downstream = downstream
            self.evidence = evidence
            self.documentID = documentID
            super.init()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            var fields: [String: Any] = [
                "document_id": documentID,
                "is_main_frame": message.frameInfo.isMainFrame,
                "frame_url": message.frameInfo.request.url?.absoluteString as Any? ?? NSNull(),
                "body_json": message.body as? String as Any? ?? NSNull()
            ]
            if let webView = message.webView {
                fields["webview_identity"] = String(describing: ObjectIdentifier(webView))
                fields["window"] = webView.window.map { String(describing: ObjectIdentifier($0)) } as Any? ?? NSNull()
                fields["scene"] = webView.window?.windowScene?.session.persistentIdentifier as Any? ?? NSNull()
            }
            if let text = message.body as? String, let data = text.data(using: .utf8),
               let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let event = envelope["event"] as? [String: Any] {
                fields["marker"] = ((event["context"] as? [String: Any])?["probe"] as? [String: Any])?["marker"]
                fields["view_id"] = (event["view"] as? [String: Any])?["id"]
            }
            evidence.record("webkit-callback", fields: fields)
            downstream.userContentController(userContentController, didReceive: message)
        }
    }
}
