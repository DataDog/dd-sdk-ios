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
        // message.body must be called within UI thread
        let messageBody = message.body
        queue.async {
            do {
                try self.emitter.send(body: messageBody)
            } catch {
                DD.logger.error("Encountered an error when receiving web view event", error: error)
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
