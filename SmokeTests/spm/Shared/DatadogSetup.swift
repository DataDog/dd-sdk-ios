/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import DatadogCore
import DatadogLogs
import DatadogTrace
import DatadogCrashReporting
#if !os(macOS)
import DatadogRUM
import DatadogSessionReplay // it should compile for iOS and tvOS, but APIs are only available on iOS
#endif
@preconcurrency import OpenTelemetryApi

#if canImport(UIKit)
import UIKit
typealias DDViewController = UIViewController
#elseif canImport(AppKit)
import AppKit
typealias DDViewController = NSViewController
#endif

@MainActor
enum DatadogSetup {
    static var logger: LoggerProtocol?
    static func initialize() {
        Datadog.initialize(
            with: Datadog.Configuration(clientToken: "abc", env: "tests"),
            trackingConsent: .granted
        )

        Logs.enable()

        CrashReporting.enable()

        logger = Logger.create(
            with: Logger.Configuration(
                remoteSampleRate: 0,
                consoleLogFormat: .short
            )
        )

        // Trace APIs must be visible:
        Trace.enable()

        logger?.info("It works")
        let span = Tracer.shared().startSpan(operationName: "this too")
        span.finish()
    }

    static func enableAndTest(viewController: DDViewController) {
        #if !os(macOS)
        // RUM APIs must be visible:
        RUM.enable(with: .init(applicationID: "app-id"))
        RUMMonitor.shared().startView(viewController: viewController)
        #endif
        
        // Trace APIs must be visible:
        Trace.enable()
        OpenTelemetry.registerTracerProvider(
            tracerProvider: OTelTracerProvider()
        )

        let otSpan = Tracer.shared().startSpan(operationName: "OT Span")
        otSpan.finish()

        // otel tracer
        let tracer = OpenTelemetry
            .instance
            .tracerProvider
            .get(instrumentationName: "", instrumentationVersion: nil)
        let otelSpan = tracer.spanBuilder(spanName: "OTel span").startSpan()
        otelSpan.end()

        #if os(iOS)
        // Session Replay API must be visible:
        SessionReplay.enable(with: .init(replaySampleRate: 0))
        #endif
    }
}
