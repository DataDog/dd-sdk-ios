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
internal protocol SessionRolloverHandler: AnyObject {
    func updateViewsIfNeeded(with rumContext: RUMCoreContext, in core: DatadogCoreProtocol)
}

@MainActor
internal class WebViewSessionRolloverHandler: SessionRolloverHandler {
#if canImport(WebKit)
    var previousIsTraceSampled: String?

    private let activeWebViews = NSMapTable<WKWebView, WebViewTrackingElements>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )

    func updateViewsIfNeeded(with rumContext: RUMCoreContext, in core: DatadogCoreProtocol) {
        let newIsTraceSampled = WebViewTracking.isTraceSampledStringValue(for: core)
        guard previousIsTraceSampled != newIsTraceSampled else {
            return
        }

        previousIsTraceSampled = newIsTraceSampled

        var activeWebViewsToUnregister = Set<WKWebView>()

        let webViewEnumerator = activeWebViews.keyEnumerator()

        while let webView = webViewEnumerator.nextObject() as? WKWebView {
            guard let elements = activeWebViews.object(forKey: webView) else {
                return
            }
            if WebViewTracking.updateUserScript(of: webView, in: core, using: elements, isTraceSampled: newIsTraceSampled) == false {
                activeWebViewsToUnregister.insert(webView)
            }
        }

        activeWebViewsToUnregister.forEach { webView in
            do {
                try WebViewSessionRolloverHandler.unregister(webView: webView, from: core)
            } catch let error {
                consolePrint("\(error)", .error)
            }
        }
    }

    func register(webView: WKWebView, elements: WebViewTrackingElements) {
        activeWebViews.setObject(elements, forKey: webView)
    }

    func unregister(webView: WKWebView) {
        activeWebViews.removeObject(forKey: webView)
    }

    static func register(webView: WKWebView, in core: DatadogCoreProtocol, using elements: WebViewTrackingElements) throws {
        let feature = try WebViewTrackingFeature.obtainOrRegisterFeature(in: core)
        feature.sessionRolloverHandler.register(webView: webView, elements: elements)
    }

    static func unregister(webView: WKWebView, from core: DatadogCoreProtocol) throws {
        let feature = try WebViewTrackingFeature.obtainOrRegisterFeature(in: core)
        feature.sessionRolloverHandler.unregister(webView: webView)
    }
#endif
}

internal class WebViewTrackingElements {
    let allowedWebViewHostsString: String
    init(allowedWebViewHostsString: String) {
        self.allowedWebViewHostsString = allowedWebViewHostsString
    }
}
