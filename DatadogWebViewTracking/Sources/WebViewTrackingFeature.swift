/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(WebKit)
import Foundation
import DatadogInternal
import WebKit

/// The WebView Tracking feature.
@MainActor
internal struct WebViewTrackingFeature: @MainActor DatadogFeature {
    static var name: String { "web-view-tracking" }

    let messageReceiver: FeatureMessageReceiver

    /// The object responsible for updating currently instrumented views when the session rolls over.
    let sessionRolloverHandler: WebViewSessionRolloverHandler

    /// Creates a new `WebViewTrackingFeature`.
    init() {
        self.sessionRolloverHandler = WebViewSessionRolloverHandler()
        self.messageReceiver = WebViewTrackingMessageReceiver(sessionRolloverHandler: sessionRolloverHandler)
    }

    /// Obtains the `WebViewTrackingFeature` for a given core, creating and registering it if necessary.
    ///
    /// Since `WebViewTracking` is a _light_ feature, there is no API to formally enable it. Since it needs to receive
    /// messages with the updated `RUMCoreContext`, it needs to exist as soon as the first `WebView` is instrumented.
    ///
    /// - Parameters:
    ///   - core: The core where the feature is, or will be registered in.
    ///
    /// - Returns: The `WebViewTrackingFeature` registered in the given core. The feature will be created and registered if
    /// it does not exist yet.
    static func obtainOrRegisterFeature(in core: DatadogCoreProtocol) throws -> WebViewTrackingFeature {
        if let feature = core.feature(named: name, type: WebViewTrackingFeature.self) {
            return feature
        }

        let feature = WebViewTrackingFeature()
        try core.register(feature: feature)
        return feature
    }
}

internal struct WebViewTrackingMessageReceiver: FeatureMessageReceiver {
    weak var sessionRolloverHandler: SessionRolloverHandler?

    func receive(message: DatadogInternal.FeatureMessage, from core: any DatadogInternal.DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            context.additionalContext(ofType: RUMCoreContext.self).map { context in
                DispatchQueue.main.async { [sessionRolloverHandler] in sessionRolloverHandler?.updateViewsIfNeeded(with: context, in: core)
                }
            }
            return true
        default:
            return false
        }
    }
}
#endif
