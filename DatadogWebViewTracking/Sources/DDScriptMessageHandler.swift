/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(WebKit)

import Foundation
import WebKit
@_spi(Internal)
import DatadogInternal

internal class DDScriptMessageHandler: NSObject, WKScriptMessageHandler {
    static let name = "DatadogEventBridge"

    let emitter: MessageEmitter

    // The provider keeps Core and tracked WebViews weak; retaining it preserves retired ownership.
    var sessionRolloverHandler: WebViewSessionRolloverHandler?

    let queue = DispatchQueue(
        label: "com.datadoghq.JSEventBridge",
        target: .global(qos: .userInteractive)
    )

    init(emitter: MessageEmitter) {
        self.emitter = emitter
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let webView = message.webView
        let hash = webView.map { String($0.hash) }
        // message.body must be called within UI thread
        let body = message.body
        #if os(iOS)
        if #available(iOS 27.0, *),
           let rolloverHandler = sessionRolloverHandler,
           rolloverHandler.hasNativeOwnership {
            enqueueMessageWithRUMContext(body: body, slotId: hash, webView: webView, rolloverHandler: rolloverHandler)
            return
        }
        #endif
        queue.async {
            self.emitter.send(body: body, slotId: hash)
        }
    }

    #if os(iOS)
    /// Captures RUM ownership before enqueueing the WebView message.
    @available(iOS 27.0, *)
    @inline(never)
    private func enqueueMessageWithRUMContext(
        body: Any,
        slotId: String?,
        webView: WKWebView?,
        rolloverHandler: WebViewSessionRolloverHandler
    ) {
        let capture = rolloverHandler.captureRUMContext(forSceneIdentifier: {
            webView?.window?.windowScene?.session.persistentIdentifier
        })
        if let capture {
            queue.async {
                self.emitter.send(body: body, slotId: slotId, capture: capture)
            }
        } else {
            queue.async {
                self.emitter.send(body: body, slotId: slotId)
            }
        }
    }
    #endif
}

extension DDScriptMessageHandler: Flushable {
    func flush() {
        queue.sync { }
    }
}

#endif
