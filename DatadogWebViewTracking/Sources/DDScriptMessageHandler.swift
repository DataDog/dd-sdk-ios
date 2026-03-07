/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(WebKit)

import Foundation
import WebKit
import DatadogInternal

@MainActor
internal class DDScriptMessageHandler: NSObject, WKScriptMessageHandler {
    static let name = "DatadogEventBridge"

    let emitter: MessageEmitter

    init(emitter: MessageEmitter) {
        self.emitter = emitter
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let hash = message.webView.map { String($0.hash) }
        let body = message.body
        emitter.send(body: body, slotId: hash)
    }
}

#endif
