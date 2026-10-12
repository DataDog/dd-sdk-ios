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
        let capture: RUMContextHandoff.Capture?
        #if os(iOS)
        if #available(iOS 27.0, *) {
            capture = sessionRolloverHandler?.captureRUMContext(forSceneIdentifier: {
                webView?.window?.windowScene?.session.persistentIdentifier
            })
        } else {
            capture = nil
        }
        #else
        capture = nil
        #endif
        queue.async {
            if let capture {
                self.emitter.send(body: body, slotId: hash, capture: capture)
            } else {
                self.emitter.send(body: body, slotId: hash)
            }
        }
    }
}

extension DDScriptMessageHandler: Flushable {
    func flush() {
        queue.sync { }
    }
}

#endif
