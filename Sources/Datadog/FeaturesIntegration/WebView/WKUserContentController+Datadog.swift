/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#if !os(tvOS)

import Foundation
import WebKit

public extension WKUserContentController {
    private static let jsCodePrefix = "/* DatadogEventBridge */"

    private var isTracking: Bool {
        return userScripts.contains {
            return $0.source.starts(with: Self.jsCodePrefix)
        }
    }

    /// Enables SDK to correlate Datadog RUM events and Logs from the WebView with native RUM session.
    ///
    /// If the content loaded in WebView uses Datadog Browser SDK (`v4.2.0+`) and matches specified `hosts`, web events will be correlated
    /// with the RUM session from native SDK.
    ///
    /// - Parameter hosts: a list of hosts instrumented with Browser SDK to capture Datadog events from
    func trackDatadogEvents(in hosts: Set<String>) {
        addDatadogMessageHandler(allowedWebViewHosts: hosts, hostsSanitizer: HostsSanitizer())
    }

    /// Disables Datadog iOS SDK and Datadog Browser SDK integration.
    ///
    /// Removes Datadog's ScriptMessageHandler and UserScript from the caller.
    /// - Note: This method **must** be called when the webview can be deinitialized.
    func stopTrackingDatadogEvents() {
        removeScriptMessageHandler(forName: DatadogMessageHandler.name)

        let nonDatadogUserScripts = userScripts.filter {
            return !$0.source.starts(with: Self.jsCodePrefix)
        }
        removeAllUserScripts()
        nonDatadogUserScripts.forEach {
            addUserScript($0)
        }
    }

    internal func addDatadogMessageHandler(allowedWebViewHosts: Set<String>, hostsSanitizer: HostsSanitizing) {
        guard !isTracking else {
              userLogger.warn("`trackDatadogEvents(in:)` was called more than once for the same WebView. Second call will be ignored. Make sure you call it only once.")
              return
           }

        let bridgeName = DatadogMessageHandler.name

        let globalRUMMonitor = Global.rum as? RUMMonitor

        var logEventConsumer: DefaultWebLogEventConsumer? = nil
        if let loggingFeature = LoggingFeature.instance {
            logEventConsumer = DefaultWebLogEventConsumer(
                userLogsWriter: loggingFeature.storage.writer,
                internalLogsWriter: InternalMonitoringFeature.instance?.logsStorage.writer,
                dateCorrector: loggingFeature.dateCorrector,
                rumContextProvider: globalRUMMonitor?.contextProvider,
                applicationVersion: loggingFeature.configuration.common.applicationVersion,
                environment: loggingFeature.configuration.common.environment
            )
        }

        var rumEventConsumer: DefaultWebRUMEventConsumer? = nil
        if let rumFeature = RUMFeature.instance {
            rumEventConsumer = DefaultWebRUMEventConsumer(
                dataWriter: rumFeature.storage.writer,
                dateCorrector: rumFeature.dateCorrector,
                contextProvider: globalRUMMonitor?.contextProvider,
                rumCommandSubscriber: globalRUMMonitor,
                dateProvider: rumFeature.dateProvider
            )
        }

        let messageHandler = DatadogMessageHandler(
            eventBridge: WebEventBridge(
                logEventConsumer: logEventConsumer,
                rumEventConsumer: rumEventConsumer
            )
        )
        add(messageHandler, name: bridgeName)

        // WebKit installs message handlers with the given name format below
        // We inject a user script to forward `window.{bridgeName}` to WebKit's format
        let webkitMethodName = "window.webkit.messageHandlers.\(bridgeName).postMessage"
        // `WKScriptMessageHandlerWithReply` returns `Promise` and `browser-sdk` expects immediate values.
        // We inject a user script to return `allowedWebViewHosts` instead of using `WKScriptMessageHandlerWithReply`
        let sanitizedHosts = hostsSanitizer.sanitized(
            hosts: allowedWebViewHosts,
            warningMessage: "The allowed WebView host configured for Datadog SDK is not valid"
        )
        let allowedWebViewHostsString = sanitizedHosts
            .map { return "\"\($0)\"" }
            .joined(separator: ",")

        let js = """
        \(Self.jsCodePrefix)
        window.\(bridgeName) = {
          send(msg) {
            \(webkitMethodName)(msg)
          },
          getAllowedWebViewHosts() {
            return '[\(allowedWebViewHostsString)]'
          }
        }
        """

        addUserScript(
            WKUserScript(
                source: js,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
    }
}

internal class DatadogMessageHandler: NSObject, WKScriptMessageHandler {
    static let name = "DatadogEventBridge"
    private let eventBridge: WebEventBridge
    let queue = DispatchQueue(
        label: "com.datadoghq.JSEventBridge",
        target: .global(qos: .userInteractive)
    )

    init(eventBridge: WebEventBridge) {
        self.eventBridge = eventBridge
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // message.body must be called within UI thread
        let messageBody = message.body
        queue.async {
            do {
                try self.eventBridge.consume(messageBody)
            } catch {
                userLogger.error("🔥 Web Event Error: \(error)")
            }
        }
    }
}

#endif
