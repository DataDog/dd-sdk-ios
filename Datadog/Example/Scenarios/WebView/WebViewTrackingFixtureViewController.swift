/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import WebKit
import Datadog

class WebViewTrackingFixtureViewController: UIViewController, WKNavigationDelegate {
    let html = """
         <head>
         <meta charset="utf-8">
         <title>Mobile SDK Detection test page</title>
         <link rel="icon" type="image/x-icon" href="./favicon.ico">
         <script type="text/javascript">
               function show(message) {
                 const p = document.createElement("p");
                 p.innerHTML = message;
                 if (document.body) {
                   document.body.appendChild(p);
                 } else {
                   window.addEventListener("DOMContentLoaded", () =>
                     document.body.appendChild(p)
                   );
                 }
               }
               function isEventBridgePresent() {
                 const isPresent = window.DatadogEventBridge;
                 if (!isPresent) {
                   show(`window.DatadogEventBridge absent!`);
                   return false;
                 }
                 if (!isViewHostAllowed()) {
                   show(
                     `This page does not respect window.DatadogEventBridge.getAllowedWebViewHosts: <br>${window.DatadogEventBridge.getAllowedWebViewHosts()}`
                   );
                   return false;
                 }
                 return true;
               }
               function getEventBridge() {
                 const datadogEventBridge = window.DatadogEventBridge;
                 return {
                   getAllowedWebViewHosts() {
                     try {
                       return JSON.parse(
                         window.DatadogEventBridge.getAllowedWebViewHosts()
                       );
                     } catch (e) {
                       show(
                         `allowWebViewHosts is not a valid json ${window.DatadogEventBridge.getAllowedWebViewHosts()}`
                       );
                     }
                     return [];
                   },
                   send(eventType, event) {
                     const eventStr = JSON.stringify({
                       eventType,
                       event,
                       tags: ["browser_sdk_version:3.6.13"],
                     });
                     datadogEventBridge.send(eventStr);
                     show(
                       `window.DatadogEventBridge: ${eventType} sent! <br><br>${eventStr}`
                     );
                   },
                 };
               }
               function sendLog() {
                 if (!isEventBridgePresent()) {
                   return;
                 }
                 try {
                   const log = {
                     date: 1635932927012,
                     error: { origin: "console" },
                     message: "console error: error",
                     session_id: "0110cab4-7471-480e-aa4e-7ce039ced355",
                     status: "error",
                     view: {
                       referrer: "",
                       url: "https://datadoghq.dev/browser-sdk-test-playground",
                     },
                   };
                   getEventBridge().send("log", log);
                 } catch (err) {
                   show(`window.DatadogEventBridge: Could not send ${err}`);
                 }
               }
               function isViewHostAllowed() {
                 return getEventBridge()
                   .getAllowedWebViewHosts()
                   .some((o) => o.includes(window.location.hostname));
               }

               show(
                 `window.DatadogEventBridge: <br>${JSON.stringify(
                   window.DatadogEventBridge
                 )}`
               );
             </script>
         </head>
         <body>
         <button onclick="sendLog()">Send dummy log</button>
         <p>window.DatadogEventBridge: <br>undefined</p></body>
         """

    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let controller = WKUserContentController()
        controller.addDatadogMessageHandler(allowedWebViewHosts: ["datadoghq.dev"])
        let config = WKWebViewConfiguration()
        config.userContentController = controller

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        view.addSubview(webView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
            window.sendLog()
        """
        webView.evaluateJavaScript(js) { res, err in
            assert(err == nil, "JS execution shouldn't return an error")
        }
    }
}
