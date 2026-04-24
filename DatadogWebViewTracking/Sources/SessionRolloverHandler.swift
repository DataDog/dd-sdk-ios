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

/// This class handles the coordination between a RUM session rollover and the tracked WebViews.
///
/// When the session rolls over, the trace sampling decision needs to be updated in the injected code on each tracked
/// WebView. In the future, more information (like the session ID itself) will also be updated to support deterministic tracing
/// on the Browser SDK.
///
/// An instance of this class must be created per core. The ``WebViewTrackingFeature`` handles that
/// automatically, there should be no need to create an instance of this class manually anywhere else.
@MainActor
internal class WebViewSessionRolloverHandler {
#if canImport(WebKit)
    /// The core that owns this handler.
    private weak var core: DatadogCoreProtocol?

    /// Creates a new RUM session rollover handler.
    ///
    /// - Parameters:
    ///   - core: The core that owns this handler.
    init(core: DatadogCoreProtocol) {
        self.core = core
    }

    /// Keeps track of the currently instrumented WebViews that are tracked by the core than owns this handler.
    ///
    /// A `NSMapTable` is used since we need to keep an instance of ``WebViewTrackingElements``
    /// per WebView, but don't want to hold a strong reference to the `WKWebView` instances.
    private let activeWebViews = NSMapTable<WKWebView, WebViewTrackingElements>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )

    /// Updates the views tracked by this handler with the new sampling decision.
    ///
    /// - Parameters:
    ///    - isTraceSampled: The trace sampling decision, already in String form. This should *always* be the output
    ///    of ``WebViewTracking/isTraceSampledStringValue(for:)``.
    func updateViews(isTraceSampled: String) {
        /*
         A note on the implementation: because the NSMapTable is kind of ancient,
         this code is a bit grotesque. Two important notes for future maintainers:

         - The collection cannot me mutated while enumerating (an exception is thrown
         if that happens). Therefore, it's necessary to collect the WebViews that should
         be unregistered, if any, in a set, and delete them after the fact.

         - NSMapTable.dictionaryRepresentation() cannot be used because it throws an
         exception it requires the map Key type to implement NSCopying and WKWebView
         does not. This hints at another reason to not use dictionaryRepresentation:
         it creates an entire copy of the dictionary, which is wasteful.

         Using weak boxes on modern Swift collections was considered, but due to the
         manual work required to remove the boxes containing deallocated objects from
         the collection, it would be even grotesquier.

         A note: do not trust NSMapTable.count. It includes the internal NSMapTable
         weak boxes with objects that were already deallocated, but not yet cleaned
         up. Expect something like

         assert(map.count > 0)
         assert(map.keyEnumerator().nextObject() == nil)

         to actually happen (this was verified with manual testing).
         */
        guard let core else {
            return
        }

        var activeWebViewsToUnregister = Set<WKWebView>()
        let webViewEnumerator = activeWebViews.keyEnumerator()

        while let webView = webViewEnumerator.nextObject() as? WKWebView {
            guard let elements = activeWebViews.object(forKey: webView) else {
                return // More grotesqueness. Should never happen, but we need to check.
            }
            if WebViewTracking.update(webView, in: core, using: elements, isTraceSampled: isTraceSampled) == false {
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

    /// Registers a WebView in this handler.
    ///
    /// - Parameters:
    ///   -  webView: The WebView to register.
    ///   - elements: The elements for this WebView. Refer to the documentation of ``WebViewTrackingElements``
    ///   for details.
    private func register(webView: WKWebView, elements: WebViewTrackingElements) {
        activeWebViews.setObject(elements, forKey: webView)
    }

    /// Unregisters a WebView from this handler.
    ///
    /// - Parameters:
    ///   - webView: The WebView to unregister.
    private func unregister(webView: WKWebView) {
        activeWebViews.removeObject(forKey: webView)
    }

    /// Registers a WebView in this handler.
    ///
    /// Call this from ``WebViewTracking/enable(webView:hosts:logsSampleRate:in:)`` when instrumenting
    /// a WebView, so it can be properly updated on RUM session rollovers.
    ///
    /// - Parameters:
    ///   - webView: The WebView to register.
    ///   - core: The core where the WebViews tracked by this handler are instrumented. This must be the core where
    ///   the ``WebViewTrackingFeature`` that owns this handler is registered. The caller is responsible for making
    ///   sure the correct core is passed in here.
    ///   - elements: The elements for this WebView. Refer to the documentation of ``WebViewTrackingElements``
    ///   for details.
    ///
    /// - throws: If a problem happens registering a newly created feature.
    static func register(webView: WKWebView, in core: DatadogCoreProtocol, using elements: WebViewTrackingElements) throws {
        let feature = try WebViewTrackingFeature.obtainOrRegisterFeature(in: core)
        feature.sessionRolloverHandler.register(webView: webView, elements: elements)
    }

    /// Unregisters a WebView from this handler.
    ///
    /// Call this from ``WebViewTracking/disable(webView:in:)`` so the WebView stops being updated
    /// on RUM session rollovers.
    ///
    /// - Parameters:
    ///   - webView: The WebView to unregister.
    ///   - core: The core where the WebViews tracked by this handler are instrumented. This must be the core where
    ///   the ``WebViewTrackingFeature`` that owns this handler is registered. The caller is responsible for making
    ///   sure the correct core is passed in here.
    ///
    /// - throws: If a problem happens registering a newly created feature.
    static func unregister(webView: WKWebView, from core: DatadogCoreProtocol) throws {
        let feature = try WebViewTrackingFeature.obtainOrRegisterFeature(in: core)
        feature.sessionRolloverHandler.unregister(webView: webView)
    }
#endif
}

/// Data provided by the user that is necessary to create the injected JavaScript bridge.
///
/// This should only hold data that never changes throughout the lifetime of the WebView, and that cannot be obtained
/// automatically.
internal final class WebViewTrackingElements: Sendable {
    /*
     Implementation note: this needs to be a class since it's a requirement for NSMapTable.
     */

    /// The hosts provided by the user, after being sanitized, and concatenated on a string ready to be injected in
    /// the JavaScript bridge.
    let allowedWebViewHostsString: String

    /// Creates a new `WebViewTrackingElements`.
    ///
    /// - Parameters:
    ///   - allowedWebViewHostsString: The hosts provided by the user, after being sanitized, and concatenated
    ///   on a string ready to be injected in the JavaScript bridge.
    init(allowedWebViewHostsString: String) {
        self.allowedWebViewHostsString = allowedWebViewHostsString
    }
}
