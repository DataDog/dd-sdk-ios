/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import UIKit
@preconcurrency import DatadogTrace
import DatadogCore
@preconcurrency import DatadogLogs
@preconcurrency import DatadogRUM
@preconcurrency import DatadogFlags
@preconcurrency import DatadogSessionReplay
@preconcurrency import OpenTelemetryApi

/**
 Compilation tests for Swift 6 migration.

 This is a canary for Swift 6 migration: all the functions below, at the time of writing, compile under Swift 5 (without strict concurrency
 checking) even if the `@preconcurrency` annotations are removed, but fail to compile under Swift 6 without the `@preconcurrency`
 annotations.

 After migrating each module, remove the `@preconcurrency` for the migrated module, and verify if this struct still compiles
 under Swift 6 strict concurrency checking.

 - Note: The code in each function does not necessarily make sense. This is never executed, it's just a way to make sure the
 code compiles under both Swift versions.
 */
struct StrictConcurrencyChecks {

    func trace() {
        let otSpan = Tracer.shared().startSpan(operationName: "OT Span")
        Task.detached {
            otSpan.keepTrace()
        }
        otSpan.finish()
    }

    func otelTracing() {
        let tracer = OpenTelemetry
            .instance
            .tracerProvider
            .get(instrumentationName: "", instrumentationVersion: nil)
        let otelSpan = tracer.spanBuilder(spanName: "OTel span").startSpan()
        otelSpan.end()
    }

    func logs() {
        var config = Logs.Configuration()
        config.eventMapper = { event in event }
        Task.detached {
            _ = config
        }
        _ = config
    }

    func rum() {
        let monitor = RUMMonitor.shared()
        Task.detached {
            monitor.stopSession()
        }
        monitor.stopSession()
    }

    func flags() {
        let client = FlagsClient.shared()
        Task.detached {
            _ = client.getBooleanValue(key: "flag", defaultValue: false)
        }
        _ = client.getBooleanValue(key: "flag", defaultValue: false)
    }

    #if os(iOS)
    @MainActor
    func sessionReplay() {
        let overrides = UIView().dd.sessionReplayPrivacyOverrides
        Task.detached {
            overrides.hide = true
        }
        overrides.hide = false
    }
    #endif

}
