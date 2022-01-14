/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import WebKit
import Datadog

class WebViewTrackingFixtureViewController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let controller = WKUserContentController()
        controller.addDatadogMessageHandler(allowedWebViewHosts: ["shopist.io"])
        let config = WKWebViewConfiguration()
        config.userContentController = controller

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        view.addSubview(webView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // swiftlint:disable:next force_unwrapping
        let request = URLRequest(url: URL(string: "https://shopist.io")!)
        webView.load(request)
    }
}
