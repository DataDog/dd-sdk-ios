/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import WebKit
import Datadog

class DebugWebviewViewController: UIViewController {
    @IBOutlet weak var rumServiceNameTextField: UITextField!

    /// When `true`, a native RUM Session between `DebugWebviewViewController` and `WebviewViewController` will be tracked.
    private var useNativeRUMSession = false

    override func viewDidLoad() {
        super.viewDidLoad()
        rumServiceNameTextField.text = (appConfiguration as? ExampleAppConfiguration)?.serviceName

        webviewURLTextField.placeholder = webviewURL
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if useNativeRUMSession {
            Global.rum.startView(viewController: self)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        if useNativeRUMSession {
            Global.rum.stopView(viewController: self)
        }
    }

    // MARK: - Starting native RUM session

    @IBAction func didTapStartNativeRUMSession(_ sender: Any) {
        useNativeRUMSession = true
        Global.rum.startView(viewController: self)
    }

    // MARK: - Starting webview

    @IBOutlet weak var webviewURLTextField: UITextField!

    private var webviewURL: String {
        guard let text = webviewURLTextField.text, !text.isEmpty else {
            return "https://datadoghq.dev/browser-sdk-test-playground/webview.html"
        }
        return text
    }

    @IBAction func didTapOpenURLInWebview(_ sender: Any) {
        if let url = URL(string: webviewURL), url.scheme != nil, url.host != nil { // basic validation
            webviewURLTextField.textColor = .black
            let webviewVC = WebviewViewController()

            webviewVC.request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData // no cache
            )
            webviewVC.navigationItem.title = "\(url.absoluteString)"
            webviewVC.useNativeRUMSession = useNativeRUMSession

            show(webviewVC, sender: nil)
        } else {
            webviewURLTextField.textColor = .red
        }
    }
}

// MARK: - Webview view controller

class WebviewViewController: UIViewController {
    /// The request to load in webview
    var request: URLRequest!
    /// When `true`, a native RUM Session between `DebugWebviewViewController` and `WebviewViewController` will be tracked.
    var useNativeRUMSession: Bool!

    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let controller = WKUserContentController()
        controller.trackDatadogEvents(in: [request.url!.host!])
        let config = WKWebViewConfiguration()
        config.userContentController = controller

        webView = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        view.addSubview(webView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        webView.load(request)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if useNativeRUMSession {
            Global.rum.startView(viewController: self)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        if useNativeRUMSession {
            Global.rum.stopView(viewController: self)
        }
    }
}
