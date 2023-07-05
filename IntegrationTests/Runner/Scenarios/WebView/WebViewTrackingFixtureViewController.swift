/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import WebKit
import DatadogCore
import DatadogWebViewTracking
import class DatadogInternal.CoreRegistry

class WebViewTrackingFixtureViewController: UIViewController, WKNavigationDelegate {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // An action sent from native iOS SDK.
        rumMonitor.addAction(type: .custom, name: "Native action")

        // Opens a webview configured to pass all its Browser SDK events to native iOS SDK.
        show(ShopistWebviewViewController(), sender: nil)
    }
}

class ShopistWebviewViewController: UIViewController {
    private let request = URLRequest(url: URL(string: "https://shopist.io")!)
    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        webView = WKWebView(frame: UIScreen.main.bounds, configuration: WKWebViewConfiguration())
        view.addSubview(webView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        WebViewTracking.enable(
            webView: webView,
            hosts: ["shopist.io"]
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        WebViewTracking.disable(webView: webView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        webView.load(request)
    }
}
