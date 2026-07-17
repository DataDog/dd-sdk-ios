/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogTrace
import DatadogCore
import OpenTelemetryApi

struct TraceScenario: Scenario {
    func start(info: TestInfo) -> UIViewController {
        Datadog.verbosityLevel = .debug

        Datadog.initialize(
            with: .e2e(info: info),
            trackingConsent: .granted
        )

        Trace.enable(
            with: .init(
                urlSessionTracking: .init(
                    firstPartyHostsTracing: .trace(
                        hosts: ["httpbin.org"],
                        sampleRate: 100,
                        traceControlInjection: .all
                    )
                ),
                // Exercise the client-side stats upload pipeline (MessagePack + deflate to
                // `/api/v0.2/stats`) end to end so Synthetics validates real intake acceptance.
                statsComputationEnabled: true
            )
        )

        OpenTelemetry.registerTracerProvider(
            tracerProvider: OTelTracerProvider()
        )

        let tracer = OpenTelemetry
            .instance
            .tracerProvider
            .get(instrumentationName: "", instrumentationVersion: nil)

        URLSessionInstrumentation.enableDurationBreakdown(
            with: .init(
                delegateClass: DistributedTraceDelegate.self
            )
        )

        let delegate = DistributedTraceDelegate()
        let urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        return OpenTelemetryTraceViewController(tracer: tracer, urlSession: urlSession)
    }
}
