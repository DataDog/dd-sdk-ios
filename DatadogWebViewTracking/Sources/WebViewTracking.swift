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
                    tracking: webView.configuration.userContentController,
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
    /// - Note: This method **must** be called when the webview can be deinitialized.
    /// 
    /// - Parameter webView: The web-view to stop tracking.
    public static func disable(webView: WKWebView) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: DDScriptMessageHandler.name)
        let others = controller.userScripts.filter { !$0.source.starts(with: Self.jsCodePrefix) }
        controller.removeAllUserScripts()
        others.forEach(controller.addUserScript)
    }

    // MARK: Internal

    static let jsCodePrefix = "/* DatadogEventBridge */"

    static func enableOrThrow(
        tracking controller: WKUserContentController,
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

        // WebKit installs message handlers with the given name format below
        // We inject a user script to forward `window.{bridgeName}` to WebKit's format
        let webkitMethodName = "window.webkit.messageHandlers.\(bridgeName).postMessage"
        // `WKScriptMessageHandlerWithReply` returns `Promise` and `browser-sdk` expects immediate values.
        // We inject a user script to return `allowedWebViewHosts` instead of using `WKScriptMessageHandlerWithReply`
        let sanitizedHosts = hostsSanitizer.sanitized(
            hosts: hosts,
            warningMessage: "The allowed WebView host configured for Datadog SDK is not valid"
        )
        let allowedWebViewHostsString = sanitizedHosts
            .map { return "\"\($0)\"" }
            .joined(separator: ",")

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
                return '[\(allowedWebViewHostsString)]'
            },
            getCapabilities() {
                return '[\(capabilities)]'
            },
            getPrivacyLevel() {
                return '\(privacyLevel.rawValue)'
            }
        }
        """

        controller.addUserScript(
            WKUserScript(
                source: js,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
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
