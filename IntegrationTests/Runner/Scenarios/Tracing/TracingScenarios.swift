/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Datadog
import DatadogTrace

/// Scenario which starts a view controller that sends bunch of spans using manual API of `Tracer`.
/// It also uses the `span.log()` to send logs.
final class TracingManualInstrumentationScenario: TestScenario {
    static let storyboardName = "TracingManualInstrumentationScenario"

    func configureFeatures() {
        guard let tracesEndpoint = Environment.serverMockConfiguration()?.tracesEndpoint else {
            return
        }

        // Register Tracer
        DatadogTracer.initialize(
            configuration: .init(
                sendNetworkInfo: true,
                customIntakeURL: tracesEndpoint
            )
        )
    }
}

/// Base scenario for Tracing instrumentation testing.
class TracingURLSessionBaseScenario: URLSessionBaseScenario {
    func configureSDK(builder: Datadog.Configuration.Builder) {
        switch setup.instrumentationMethod {
        case .directWithAdditionalFirstyPartyHosts:
            _ = builder.trackURLSession()
        case .directWithGlobalFirstPartyHosts, .inheritance, .composition:
            _ = builder.trackURLSession(
                firstPartyHosts: [customGETResourceURL.host!, customPOSTRequest.url!.host!, badResourceURL.host!]
            )
        }
    }

    func configureFeatures() {
        guard let tracesEndpoint = Environment.serverMockConfiguration()?.tracesEndpoint else {
            return
        }

        let firstPartyHosts: Set<String>
        switch setup.instrumentationMethod {
        case .directWithAdditionalFirstyPartyHosts:
            firstPartyHosts = []
        case .directWithGlobalFirstPartyHosts, .inheritance, .composition:
            firstPartyHosts = [customGETResourceURL.host!, customPOSTRequest.url!.host!, badResourceURL.host!]
        }

        // Register Tracer
        DatadogTracer.initialize(
            configuration: .init(
                sendNetworkInfo: true,
                customIntakeURL: tracesEndpoint,
                spanEventMapper: {
                    var span = $0
                    if span.tags[OTTags.httpUrl] != nil {
                        span.tags[OTTags.httpUrl] = "redacted"
                    }
                    return span
                }
            ),
            distributedTracingConfiguration: .init(
                firstPartyHosts: firstPartyHosts,
                tracingSamplingRate: 100
            )
        )
    }
}

/// Scenario which uses Tracing auto instrumentation feature to track bunch of first party network requests
/// sent with `URLSession` (Swift) from the first VC and ignores other third party requests send from second VC.
final class TracingURLSessionScenario: TracingURLSessionBaseScenario, TestScenario {
    static let storyboardName = "URLSessionScenario"

    override func configureSDK(builder: Datadog.Configuration.Builder) { super.configureSDK(builder: builder) }
    override func configureFeatures() { super.configureFeatures() }
}

/// Scenario which uses Tracing auto instrumentation feature to track bunch of first party network requests
/// sent with `NSURLSession` (Objective-C) from the first VC and ignores other third party requests send from second VC.
@objc
final class TracingNSURLSessionScenario: TracingURLSessionBaseScenario, TestScenario {
    static let storyboardName = "NSURLSessionScenario"

    override func configureSDK(builder: Datadog.Configuration.Builder) { super.configureSDK(builder: builder) }
    override func configureFeatures() { super.configureFeatures() }
}
