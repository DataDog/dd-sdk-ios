/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Datadog
import DatadogTrace
import DatadogLogs

/// Scenario which starts a view controller that sends bunch of spans using manual API of `Tracer`.
/// It also uses the `span.log()` to send logs.
final class TracingManualInstrumentationScenario: TestScenario {
    static let storyboardName = "TracingManualInstrumentationScenario"

    func configureFeatures() {
        // Register Tracer
        DatadogTracer.initialize(
            configuration: .init(
                sendNetworkInfo: true,
                customIntakeURL: Environment.serverMockConfiguration()?.tracesEndpoint
            )
        )

        // Enable Logs
        Logs.enable(
            with: Logs.Configuration(
                customIntakeURL: Environment.serverMockConfiguration()?.logsEndpoint
            )
        )
    }
}

/// Scenario which uses Tracing auto instrumentation feature to track bunch of first party network requests
/// sent with `URLSession` (Swift) from the first VC and ignores other third party requests send from second VC.
final class TracingURLSessionScenario: URLSessionBaseScenario, TestScenario {
    static let storyboardName = "URLSessionScenario"

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .enableRUM(false)
        super.configureSDK(builder: builder)
    }
}

/// Scenario which uses Tracing auto instrumentation feature to track bunch of first party network requests
/// sent with `NSURLSession` (Objective-C) from the first VC and ignores other third party requests send from second VC.
@objc
final class TracingNSURLSessionScenario: URLSessionBaseScenario, TestScenario {
    static let storyboardName = "NSURLSessionScenario"

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .enableRUM(false)
        super.configureSDK(builder: builder)
    }
}
