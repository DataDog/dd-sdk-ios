/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import Foundation
import WebKit
import DatadogInternal

internal class DDScriptMessageHandler: NSObject, WKScriptMessageHandler {
    static let name = "DatadogEventBridge"

    let emitter: MessageEmitter

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
        let hash = message.webView.map { String($0.hash) }
        // message.body must be called within UI thread
        let body = message.body
        queue.async {
            self.emitter.send(body: body, slotId: hash)
        }
    }
}

extension DDScriptMessageHandler: Flushable {
    func flush() {
        queue.sync { }
    }
}

#endif
