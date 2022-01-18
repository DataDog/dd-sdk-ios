/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import WebKit
import Datadog

class WebViewTrackingFixtureViewController: UIViewController, WKNavigationDelegate {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // An action sent from native iOS SDK.
        Global.rum.addUserAction(type: .custom, name: "Native action")

        // Opens a webview configured to pass all its Browser SDK events to native iOS SDK.
        show(ShopistWebviewViewController(), sender: nil)
    }
}

class ShopistWebviewViewController: UIViewController {
    private let request = URLRequest(url: URL(string: "https://shopist.io")!)
    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let controller = WKUserContentController()
        controller.addDatadogMessageHandler(allowedWebViewHosts: ["shopist.io"])
        let config = WKWebViewConfiguration()
        config.userContentController = controller

        webView = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        view.addSubview(webView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        webView.load(request)
    }
}
