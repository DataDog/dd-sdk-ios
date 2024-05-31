/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import WebKit
import DatadogWebViewTracking

class SessionReplayWebViewController: UIViewController, WKUIDelegate {
    var webView: WKWebView!

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = self
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        WebViewTracking.enable(
            webView: webView,
            hosts: ["datadoghq.dev"],
            sessionReplayConfiguration: WebViewTracking.SessionReplayConfiguration(
                privacyLevel: .allow
            )
        )

        let url = URL(string: "https://datadoghq.dev/browser-sdk-test-playground/webview-support")!
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func load(url string: String) {
        let url = URL(string: string)!
        let request = URLRequest(url: url)
        webView.load(request)
    }
}
