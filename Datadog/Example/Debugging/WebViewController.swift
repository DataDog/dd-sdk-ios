/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import WebKit

class MessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("""
        🌍 New message:
        - message.name = '\(message.name)'
        - message.world = '\(String(describing: message.world))'
        - message.body = '\(String(describing: message.body))'
        """)
    }
}

class WebViewController: UIViewController, WKUIDelegate, WKNavigationDelegate {
    private var webView: WKWebView!

    override func viewDidLoad() {
        let js = """
            window.DatadogJsInterface = { send(msg) { window.webkit.messageHandlers.DatadogJSHandler.postMessage(msg) } }
            """
        let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)

        let controller = WKUserContentController()
        controller.addUserScript(script)
        controller.add(MessageHandler(), name: "DatadogJSHandler")

        let config = WKWebViewConfiguration()
        config.userContentController = controller

//        let defaultConfig = WKWebViewConfiguration()

        self.webView = WKWebView(frame: UIScreen.main.bounds, configuration: config)
//        self.webView.configuration.userContentController = controller

//        self.webView.navigationDelegate = self
//        self.webView.uiDelegate = self

        view.addSubview(webView)

        let url = URL(string: "https://datadoghq.dev/browser-sdk-test-playground/webview.html")!
        let req = URLRequest(url: url)
        self.webView.load(req)
    }

//    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
//        let js = """
//            window.DatadogJsInterface = {};
//            """
//        webView.evaluateJavaScript(js) { any, err in
//            print(any)
//            print(err)
//        }
//
//        decisionHandler(.allow, .init())
//    }

//    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
//        let js = """
//            window.DatadogJsInterface = {};
//            """
//        webView.evaluateJavaScript(js) { any, err in
//            print(any)
//            print(err)
//        }
//
//        decisionHandler(.allow)
//    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let js = """
            window.DatadogJsInterface = {};
            """
        webView.evaluateJavaScript(js) { any, err in
            print(any)
            print(err)
        }
    }

//    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
//        let js = """
//            window.DatadogJsInterface = {};
//            """
//        webView.evaluateJavaScript(js) { any, err in
//            print(any)
//            print(err)
//        }
//        // detected after 300ms
//    }

//    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
//        let js = """
//            window.DatadogJsInterface = {};
//            """
//        webView.evaluateJavaScript(js) { any, err in
//            print(any)
//            print(err)
//        }
//        // detected after 300ms
//    }

//    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
//        let js = """
//            window.DatadogJsInterface = {};
//            """
//        webView.evaluateJavaScript(js) { any, err in
//            print(any)
//            print(err)
//        }
//
//        completionHandler(.performDefaultHandling, nil)
//    }
}
