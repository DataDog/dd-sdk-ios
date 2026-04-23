/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
#if canImport(WebKit)
import WebKit
#endif

@MainActor
internal struct WebViewTrackingFeature: @MainActor DatadogFeature {
    static var name: String { "web-view-tracking" }

    let messageReceiver: FeatureMessageReceiver

    let sessionRolloverHandler: WebViewSessionRolloverHandler

    init() {
        self.sessionRolloverHandler = WebViewSessionRolloverHandler()
        self.messageReceiver = WebViewTrackingMessageReceiver(sessionRolloverHandler: sessionRolloverHandler)
    }

    fileprivate static func obtainOrRegisterFeature(in core: DatadogCoreProtocol) throws -> WebViewTrackingFeature {
        if let feature = core.feature(named: name, type: WebViewTrackingFeature.self) {
            return feature
        }

        let feature = WebViewTrackingFeature()
        try core.register(feature: feature)
        return feature
    }
}

@MainActor
internal protocol SessionRolloverHandlerHandler: AnyObject {
    func updateViewsIfNeeded(with rumContext: RUMCoreContext, in core: DatadogCoreProtocol)
}

@MainActor
internal class WebViewSessionRolloverHandler: SessionRolloverHandlerHandler {
    var previousIsTraceSampled: String?

#if canImport(WebKit)
    private let activeWebViews = NSHashTable<WKWebView>(options: [.weakMemory], capacity: 2)
#endif

    func updateViewsIfNeeded(with rumContext: RUMCoreContext, in core: DatadogCoreProtocol) {
        let newIsTraceSampled = Self.isTraceSampledStringValue(for: core)
        guard previousIsTraceSampled != newIsTraceSampled else {
            return
        }

        previousIsTraceSampled = newIsTraceSampled

#if canImport(WebKit)
        let js =
"""
if (window.\(DDScriptMessageHandler.name)) {
    window.\(DDScriptMessageHandler.name).getIsTraceSampled = () => \(newIsTraceSampled)
}
"""

        activeWebViews.allObjects.forEach { webView in
            webView.evaluateJavaScript(js)
        }
#endif
    }

    func register(webView: WKWebView) {
#if canImport(WebKit)
        activeWebViews.add(webView)
#endif
    }

    func unregister(webView: WKWebView) {
#if canImport(WebKit)
        activeWebViews.remove(webView)
#endif
    }

    static func register(webView: WKWebView, in core: DatadogCoreProtocol) throws {
        let feature = try WebViewTrackingFeature.obtainOrRegisterFeature(in: core)
        feature.sessionRolloverHandler.register(webView: webView)
    }

    static func unregister(webView: WKWebView, from core: DatadogCoreProtocol) throws {
        let feature = try WebViewTrackingFeature.obtainOrRegisterFeature(in: core)
        feature.sessionRolloverHandler.unregister(webView: webView)
    }

    static func isTraceSampledStringValue(for core: DatadogCoreProtocol) -> String {
        let rum = core.feature(
            named: RUMFeatureName,
            type: RUMFirstPartyHostsTracingDecisionProvider.self
        )

        return rum.map {
            switch $0.areFirstPartyHostsTraced {
            case .some(true): "true"
            case .some(false): "false"
            case .none: "null"
            }
        } ?? "null"
    }
}

internal struct WebViewTrackingMessageReceiver: FeatureMessageReceiver {
    weak var sessionRolloverHandler: SessionRolloverHandlerHandler?

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
