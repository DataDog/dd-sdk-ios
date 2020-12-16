/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog

let allTracingScenarios: [TestScenario.Type] = [
    TracingManualInstrumentationScenario.self,
    TracingURLSessionScenario.self,
    TracingNSURLSessionScenario.self,
]

/// Scenario which starts a view controller that sends bunch of spans using manual API of `Tracer`.
/// It also uses the `span.log()` to send logs.
struct TracingManualInstrumentationScenario: TestScenario {
    static let storyboardName = "TracingManualInstrumentationScenario"
}

/// Scenario which uses Tracing auto instrumentation feature to track bunch of first party network requests
/// sent with `URLSession` (Swift) from the first VC and ignores other third party requests send from second VC.
final class TracingURLSessionScenario: URLSessionBaseScenario, TestScenario {
    static let storyboardName = "URLSessionScenario"
    static func envIdentifier() -> String { "TracingURLSessionScenario" }

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
    static func envIdentifier() -> String { "TracingNSURLSessionScenario" }

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .enableRUM(false)

        super.configureSDK(builder: builder)
    }
}
