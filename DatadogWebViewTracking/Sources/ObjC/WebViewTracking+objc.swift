/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if canImport(WebKit)
import WebKit

@objc(DDWebViewTracking)
@_spi(objc)
public final class objc_WebViewTracking: NSObject {
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
    ///   - core: Datadog SDK core to use for tracking.
    @objc
    public static func enable(
        webView: WKWebView,
        hosts: Set<String> = [],
        logsSampleRate: SampleRate = .maxSampleRate
    ) {
        WebViewTracking.enable(
            webView: webView,
            hosts: hosts,
            logsSampleRate: logsSampleRate
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
#endif
