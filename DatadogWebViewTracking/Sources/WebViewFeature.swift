/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The web-view tracking feature for core-registration.
///
/// This Feature only keeps references to ``DDScriptMessageHandler`` for tearing down
/// instrumentation.
internal final class WebViewFeature: DatadogFeature {
    static let name = "DatadogWebViewTracking"

    let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()

    /// References to registered ``DDScriptMessageHandler``.
    @ReadWriteLock
    var handlers: [ObjectIdentifier: DDScriptMessageHandler] = [:]
}

extension DatadogCoreProtocol {
    /// Core extension for registering ``DDScriptMessageHandler`` handlers.
    ///
    /// - Parameters:
    ///   - scriptMessageHandler: The ``DDScriptMessageHandler`` handler to register.
    ///   - identifier: The handler identifier.
    func register(scriptMessageHandler: DDScriptMessageHandler, forIdentifier identifier: ObjectIdentifier) throws {
        let feature = get(feature: WebViewFeature.self) ?? .init()
        feature.handlers[identifier] = scriptMessageHandler
        try register(feature: feature)
    }

    /// Core extension for unregistering a ``DDScriptMessageHandler`` instance.
    /// - Parameter identifier: The ``DDScriptMessageHandler`` identifier.
    func unregisterScriptMessageHandler(forIdentifier identifier: ObjectIdentifier) {
        let feature = get(feature: WebViewFeature.self)
        feature?.handlers.removeValue(forKey: identifier)
    }
}

extension WebViewFeature: DispatchContinuation {
    func notify(_ continuation: @escaping () -> Void) {
        DispatchContinuationSequence(group: handlers.values)
            .notify(continuation)
    }
}
