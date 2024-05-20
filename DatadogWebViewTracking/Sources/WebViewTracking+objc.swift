/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
#if os(tvOS)
#warning("Datadog WebView Tracking does not support tvOS")
#else
import WebKit
#endif

@objc
public final class DDWebViewTracking: NSObject {
    override private init() { }

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
    ///   - sessionReplayConfiguration: Session Replay configuration to enable linking Web and Native replays.
    ///   - core: Datadog SDK core to use for tracking.
    @objc
    public static func enable(
        webView: WKWebView,
        hosts: Set<String> = [],
        logsSampleRate: Float = 100,
        with configuration: DDWebViewTrackingSessionReplayConfiguration? = nil
    ) {
        WebViewTracking.enable(
            webView: webView,
            hosts: hosts,
            logsSampleRate: logsSampleRate,
            sessionReplayConfiguration: configuration?.toSwift
        )
    }

    /// Disables Datadog iOS SDK and Datadog Browser SDK integration.
    ///
    /// Removes Datadog's ScriptMessageHandler and UserScript from the caller.
    /// - Note: This method **must** be called when the webview can be deinitialized.
    ///
    /// - Parameter webView: The web-view to stop tracking.
    @objc
    public static func disable(
        webView: WKWebView
    ) {
        WebViewTracking.disable(webView: webView)
    }
}

/// The Session Replay configuration to capture records coming from the web view.
///
/// Setting the Session Replay configuration in `WebViewTracking` will enable transmitting replay data from
/// the Datadog Browser SDK installed in the web page. Datadog will then be able to combine the native
/// and web recordings in a single replay.
@objc
public final class DDWebViewTrackingSessionReplayConfiguration: NSObject {
    /// Available privacy levels for content masking.
    @objc
    public enum DDPrivacyLevel: Int {
        /// Record all content.
        case allow
        /// Mask all content.
        case mask
        /// Mask input elements, but record all other content.
        case maskUserInput

        internal var toSwift: WebViewTracking.SessionReplayConfiguration.PrivacyLevel {
            switch self {
            case .allow: .allow
            case .mask: .mask
            case .maskUserInput: .maskUserInput
            }
        }
    }

    /// The privacy level to use for the web view replay recording.
    @objc public var privacyLevel: DDPrivacyLevel

    /// Creates Webview Session Replay configuration.
    ///
    /// - Parameters:
    ///   - privacyLevel: The way sensitive content (e.g. text) should be masked. Default: `.mask`.
    @objc
    override public init() {
        self.privacyLevel = .mask
    }

    /// Creates Webview Session Replay configuration.
    ///
    /// - Parameters:
    ///   - privacyLevel: The way sensitive content (e.g. text) should be masked. Default: `.mask`.
    @objc
    public init(
        privacyLevel: DDPrivacyLevel
    ) {
        self.privacyLevel = privacyLevel
    }

    internal var toSwift: WebViewTracking.SessionReplayConfiguration {
        return .init(
            privacyLevel: privacyLevel.toSwift
        )
    }
}
