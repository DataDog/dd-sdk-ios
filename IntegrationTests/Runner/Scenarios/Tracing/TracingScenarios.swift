/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
import DatadogTrace
import DatadogLogs

/// Scenario which starts a view controller that sends bunch of spans using manual API of `Tracer`.
/// It also uses the `span.log()` to send logs.
final class TracingManualInstrumentationScenario: TestScenario {
    static let storyboardName = "TracingManualInstrumentationScenario"

    func configureFeatures() {
        // Enable Trace
        Trace.enable(
            with: Trace.Configuration(
                sampleRate: 100,
                networkInfoEnabled: true,
                customEndpoint: Environment.serverMockConfiguration()?.tracesEndpoint
            )
        )

        // Enable Logs
        Logs.enable(
            with: Logs.Configuration(
                customEndpoint: Environment.serverMockConfiguration()?.logsEndpoint
            )
        )
    }
}

/// Base scenario for Tracing instrumentation testing.
class TracingURLSessionBaseScenario: URLSessionBaseScenario {
    func configureFeatures() {
        var config = Trace.Configuration(sampleRate: 100)
        config.networkInfoEnabled = true
        config.customEndpoint = Environment.serverMockConfiguration()?.tracesEndpoint
        config.eventMapper = {
            var span = $0
            if span.tags[OTTags.httpUrl] != nil {
                span.tags[OTTags.httpUrl] = "redacted"
            }
            return span
        }

        switch setup.instrumentationMethod {
        case .delegateUsingFeatureFirstPartyHosts:
            config.urlSessionTracking = .init(
                firstPartyHostsTracing: .trace(
                    hosts: [
                        customGETResourceURL.host!,
                        customPOSTRequest.url!.host!,
                        badResourceURL.host!,
                    ],
                    sampleRate: 100
                )
            )
        case .delegateWithAdditionalFirstPartyHosts:
            config.urlSessionTracking = .init(
                firstPartyHostsTracing: .trace(hosts: [], sampleRate: 100) // hosts will be set through `DDURLSessionDelegate`
            )
        }
        Trace.enable(with: config)
    }
}

/// Scenario which uses Tracing auto instrumentation feature to track bunch of first party network requests
/// sent with `URLSession` (Swift) from the first VC and ignores other third party requests send from second VC.
final class TracingURLSessionScenario: TracingURLSessionBaseScenario, TestScenario {
    static let storyboardName = "URLSessionScenario"

    override func configureFeatures() { super.configureFeatures() }
}

/// Scenario which uses Tracing auto instrumentation feature to track bunch of first party network requests
/// sent with `NSURLSession` (Objective-C) from the first VC and ignores other third party requests send from second VC.
@objc
final class TracingNSURLSessionScenario: TracingURLSessionBaseScenario, TestScenario {
    static let storyboardName = "NSURLSessionScenario"

    override func configureFeatures() { super.configureFeatures() }
}
