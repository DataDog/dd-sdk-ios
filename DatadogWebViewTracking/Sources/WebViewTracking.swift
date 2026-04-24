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

/// Real User Monitoring allows you to monitor web views and eliminate blind spots in your hybrid iOS applications.
///
/// # Prerequisites:
/// Set up the web page you want rendered on your mobile iOS and tvOS application with the RUM Browser SDK
/// first. For more information, see [RUM Browser Monitoring](https://docs.datadoghq.com/real_user_monitoring/browser/#npm).
///
/// You can perform the following:
/// - Track user journeys across web and native components in mobile applications
/// - Scope the root cause of latency to web pages or native components in mobile applications
/// - Support users that have difficulty loading web pages on mobile devices
public enum WebViewTracking {
#if canImport(WebKit)
    /// Enables SDK to correlate Datadog RUM events and Logs from the WebView with native RUM session.
    /// 
    /// If the content loaded in WebView uses Datadog Browser SDK (`v4.2.0+`) and matches specified
    /// `hosts`, web events will be correlated with the RUM session from native SDK.
    ///
    /// - Parameters:
    ///   - webView: The web-view to track.
    ///   - hosts: A set of hosts instrumented with Browser SDK to capture Datadog events from.
    ///   - logsSampleRate: The sampling rate for logs coming from the WebView. Must be a value between `0` and `100`,
    ///   where 0 means no logs will be sent and 100 means all will be uploaded. Default: `100`.
    ///   - core: Datadog SDK core to use for tracking.
    public static func enable(
        webView: WKWebView,
        hosts: Set<String> = [],
        logsSampleRate: SampleRate = .maxSampleRate,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            // To ensure the correct registration order between Core and Features,
            // the entire initialization flow is synchronized on the main thread.
            try runOnMainThreadSync {
                try enableOrThrow(
                    tracking: webView,
                    hosts: hosts,
                    hostsSanitizer: HostsSanitizer(),
                    logsSampleRate: logsSampleRate,
                    in: core
                )
            }
        } catch let error {
            consolePrint("\(error)", .error)
        }
    }

    /// Disables Datadog iOS SDK and Datadog Browser SDK integration.
    ///
    /// Removes Datadog's ScriptMessageHandler and UserScript from the caller.
    /// - Note: This method **must** be called when the WebView can be deinitialized.
    ///
    /// - Parameters:
    ///   - webView: The web-view to stop tracking.
    ///   - core: Datadog SDK core where the WebView was tracked.
    public static func disable(webView: WKWebView, in core: DatadogCoreProtocol = CoreRegistry.default) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: DDScriptMessageHandler.name)
        let others = controller.userScripts.filter { !$0.source.starts(with: Self.jsCodePrefix) }
        controller.removeAllUserScripts()
        others.forEach(controller.addUserScript)
        do {
            try runOnMainThreadSync {
                try WebViewSessionRolloverHandler.unregister(webView: webView, from: core)
            }
        } catch let error {
            consolePrint("\(error)", .error)
        }
    }

    // MARK: Internal

    static let jsCodePrefix = "/* DatadogEventBridge */"

    @MainActor
    static func enableOrThrow(
        tracking webView: WKWebView,
        hosts: Set<String>,
        hostsSanitizer: HostsSanitizing,
        logsSampleRate: Float,
        in core: DatadogCoreProtocol
    ) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `WebViewTracking.enable(webView:)`."
            )
        }

        let controller = webView.configuration.userContentController
        let isTracking = controller.userScripts.contains { $0.source.starts(with: Self.jsCodePrefix) }
        guard !isTracking else {
            DD.logger.warn("`startTrackingDatadogEvents(core:hosts:)` was called more than once for the same WebView. Second call will be ignored. Make sure you call it only once.")
            return
        }

        let bridgeName = DDScriptMessageHandler.name

        let messageHandler = DDScriptMessageHandler(
            emitter: MessageEmitter(
                logsSampler: Sampler(samplingRate: logsSampleRate),
                core: core
            )
        )

        // Prevent fatal error: `Attempt to add script message handler with name 'DatadogEventBridge' when one already exists.`
        controller.removeScriptMessageHandler(forName: bridgeName)
        controller.add(messageHandler, name: bridgeName)

        // `WKScriptMessageHandlerWithReply` returns `Promise` and `browser-sdk` expects immediate values.
        // We inject a user script to return `allowedWebViewHosts` instead of using `WKScriptMessageHandlerWithReply`
        let sanitizedHosts = hostsSanitizer.sanitized(
            hosts: hosts,
            warningMessage: "The allowed WebView host configured for Datadog SDK is not valid"
        )
        let allowedWebViewHostsString = sanitizedHosts
            .map { return "\"\($0)\"" }
            .joined(separator: ",")

        let elements = WebViewTrackingElements(allowedWebViewHostsString: allowedWebViewHostsString)
        let isTraceSampled = WebViewTracking.isTraceSampledStringValue(for: core)

        try WebViewSessionRolloverHandler.register(webView: webView, in: core, using: elements)

        injectUserScript(on: webView, in: core, using: elements, isTraceSampled: isTraceSampled)

        core.telemetry.usage(event: .trackWebView)
    }

    /// Injects the Javascript bridge code in the WebView user scripts.
    ///
    /// - Important: This function does not check if the script is already there and should be called *only* when
    /// we know it's not. Make sure to test for this situation, or guarantee it wont happen, before calling this function.
    ///
    /// - Parameters:
    ///   - webView: The WebView where the script will be injected into.
    ///   - core: The core where the WebView is instrumented.
    ///   - elements: The elements used to generate the injected script.
    ///   - isTraceSampled: The trace sampling decision, already in String form. This should *always* be the output
    ///   of ``WebViewTracking/isTraceSampledStringValue(for:)``.
    @MainActor
    private static func injectUserScript(on webView: WKWebView, in core: DatadogCoreProtocol, using elements: WebViewTrackingElements, isTraceSampled: String) {
        let bridgeName = DDScriptMessageHandler.name

        // WebKit installs message handlers with the given name format below
        // We inject a user script to forward `window.{bridgeName}` to WebKit's format
        let webkitMethodName = "window.webkit.messageHandlers.\(bridgeName).postMessage"

        let sessionReplay = core.feature(
            named: SessionReplayFeatureName,
            type: SessionReplayConfiguration.self
        )

        let privacyLevel = sessionReplay.map {
            Self.determineWebViewPrivacyLevel(
                textPrivacy: $0.textAndInputPrivacyLevel,
                imagePrivacy: $0.imagePrivacyLevel,
                touchPrivacy: $0.touchPrivacyLevel
            )
        } ?? .mask

        // Share native capabilities with Browser SDK
        let capabilities = sessionReplay != nil ? "\"records\"" : ""

        let js = """
        \(Self.jsCodePrefix)
        window.\(bridgeName) = {
            send(msg) {
                \(webkitMethodName)(msg)
            },
            getAllowedWebViewHosts() {
                return '[\(elements.allowedWebViewHostsString)]'
            },
            getCapabilities() {
                return '[\(capabilities)]'
            },
            getPrivacyLevel() {
                return '\(privacyLevel.rawValue)'
            },
            getIsTraceSampled() {
                return \(Self.isTraceSampledStringValue(for: core))
            }
        }
        """

        webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source: js,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
    }

    /// Updates this WebView instrumentation on session rollovers.
    ///
    /// Two things need to be done on session rollovers:
    /// * Update the script stored in `userScripts` with the new decision. This guarantees that any new pages loaded
    /// in the WebView will have the updated bridge and thus the updated sampling decision.
    /// * Run a bit of JavaScript code to update the bridge on the currently loaded page. This guarantees the current page
    /// gets the most up to date decision as well.
    ///
    /// - Parameters:
    ///   - webView: The WebView whose instrumentation should be updated.
    ///   - core: The core where the WebView is instrumented.
    ///   - elements: The elements used to generate the injected script.
    ///   - isTraceSampled: The trace sampling decision, already in String form. This should *always* be the output
    ///   of ``WebViewTracking/isTraceSampledStringValue(for:)``.
    ///
    /// - Returns: `true` if the view was instrumented before (and therefore was re-instrumented correctly), `false`
    /// if the view was not instrumented and should be unregistered from the `WebViewSessionRolloverHandler`.
    /// Note that if the view was instrumented before, this function always returns `true`, it cannot fail instrumentation in
    /// that situation. Therefore, `false` guarantees the view wasn't instrumented. It's possible views are registered in
    /// `WebViewSessionRolloverHandler` and not instrumented in the rare situation where
    ///  ``WebViewTracking/disable(webView:in:)`` was called on the wrong core.
    @MainActor
    static func update(_ webView: WKWebView, in core: DatadogCoreProtocol, using elements: WebViewTrackingElements, isTraceSampled: String) -> Bool {
        let controller = webView.configuration.userContentController

        // Remove our script
        let others = controller.userScripts.filter { !$0.source.starts(with: Self.jsCodePrefix) }
        guard others.count != controller.userScripts.count else {
            // If this happens, the view is not instrumented any more, but we still think it is.
            // This may happen in the rare situation the WebView was registered in a specific, non
            // default core, and WebViewTracking.disable(…) was called without specifying the
            // correct core.
            // To avoid future calls, return false so it can be unregistered.

            return false
        }
        controller.removeAllUserScripts()
        others.forEach(controller.addUserScript)

        // Re-insert updated script
        injectUserScript(on: webView, in: core, using: elements, isTraceSampled: isTraceSampled)

        // Run code to update the current page
        let js =
        """
        if (window.\(DDScriptMessageHandler.name)) {
            window.\(DDScriptMessageHandler.name).getIsTraceSampled = () => \(isTraceSampled)
        }
        """

        webView.evaluateJavaScript(js)

        return true
    }

    /// Obtains the trace sampling decision for the given core, in `String` form ready to be used in the injected scripts.
    ///
    /// This is the decision if requests should be traced. The decision is positive if:
    /// * RUM is enabled, and the decision to sample the current session is positive; and
    /// * `urlSessionTracking.firstPartyHostsTracing` is configured in `RUM.Configuration`; and
    /// * The sampling decision for `firstPartyHostsTracing` is positive.
    ///
    /// Note the hosts configured in RUM's `urlSessionTracking.firstPartyHostsTracing` do not need to
    /// match the ones being tracked by a WebView. The sampling decision is the same regardless.
    ///
    /// The returned values are the following strings:
    /// * `true` if the sampling decision is positive as explained above.
    /// * `false` if the sampling decision is negative. This happens if RUM is enabled but sampled out, _or_ if
    /// `urlSessionTracking.firstPartyHostsTracing` is configured but sampled out.
    /// * `null` if no sampling decision was made. This happens if RUM is not configured, _or_ if
    /// `urlSessionTracking.firstPartyHostsTracing` is not configured.
    ///
    /// Note that `false` is not returned if either of the conditions for `null` happen. The goal of `null` is allowing
    /// the Browser SDK to make its own sampling decision according to its own configuration, since the iOS side was
    /// not configured to do so.
    ///
    /// - Parameters:
    ///   - core: The core used for the instrumentation. Make sure this is consistent with the core used to instrument
    ///   the view, since the sampling decision can be different in multiple cores.
    ///
    /// - Returns: The string ready to be injected in the bridge as explained above.
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

    /// Conversion matrix from global privacy level to fine-grained privaly levels.
    /// Although `SessionReplayPrivacyLevel` is deprecated on mobile,
    /// it is still needed to configure the browser SDK for the web integration,
    /// which currently doesn't support fine-grained priavcy options.
    internal static func determineWebViewPrivacyLevel(
            textPrivacy: TextAndInputPrivacyLevel,
            imagePrivacy: ImagePrivacyLevel,
            touchPrivacy: TouchPrivacyLevel
        ) -> SessionReplayPrivacyLevel {
            switch (textPrivacy, imagePrivacy, touchPrivacy) {
            case (.maskSensitiveInputs, .maskNone, .show):
                return .allow
            case (.maskSensitiveInputs, .maskNone, .hide):
                return .mask
            case (.maskSensitiveInputs, .maskNonBundledOnly, _):
                return .mask
            case (.maskSensitiveInputs, .maskAll, _):
                return .mask

            case (.maskAllInputs, .maskNone, .show):
                return .maskUserInput
            case (.maskAllInputs, .maskNone, .hide):
                return .mask
            case (.maskAllInputs, .maskNonBundledOnly, _):
                return .mask
            case (.maskAllInputs, .maskAll, _):
                return .mask

            case (.maskAll, _, _):
                return .mask
            }
        }
#endif
}

extension WebViewTracking: InternalExtended { }
extension InternalExtension where ExtendedType == WebViewTracking {
    /// Abstract Message Emitter definition.
    public class AbstractMessageEmitter {
        /// Sends a web-view message.
        ///
        /// - Parameter message: The message to send
        public func send(body: Any, slotId: String? = nil) {}
    }

    /// Creates a web-view message emitter for cross-platform.
    ///
    /// Cross platform SDKs should instantiate a `MessageEmitter` implementation from
    /// this method and pass WebView related messages using the message bus of the core.
    ///
    /// - Parameters:
    ///   - core: The Datadog SDK core instance
    ///   - logsSampleRate: The sampling rate for logs coming from the WebView. Must be a value between `0` and `100`. Default: `100`.
    /// - Returns: A `MessageEmitter` instance
    public static func messageEmitter(
        in core: DatadogCoreProtocol,
        logsSampleRate: SampleRate = .maxSampleRate
    ) -> AbstractMessageEmitter {
        return MessageEmitter(
            logsSampler: Sampler(samplingRate: logsSampleRate),
            core: core
        )
    }
}
