/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
import DatadogTrace
import DatadogLogs
import DatadogRUM

class RUMAndTracingURLSessionBaseScenario: URLSessionBaseScenario, TestScenario {
    static var storyboardName: String { "RUMAndTracingScenarios" }

    required override init() {
        super.init()
    }

    func configureFeatures() {
        var traceConfig = Trace.Configuration(sampleRate: 100)
        traceConfig.networkInfoEnabled = true
        traceConfig.customEndpoint = Environment.serverMockConfiguration()?.tracesEndpoint
        traceConfig.eventMapper = {
            var span = $0
            if span.tags[OTTags.httpUrl] != nil {
                span.tags[OTTags.httpUrl] = "redacted"
            }
            return span
        }

        Trace.enable(with: traceConfig)

        var rumConfig = RUM.Configuration(applicationID: "rum-application-id")
        rumConfig.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()

        switch setup.instrumentationMethod {
        case .delegateUsingFeatureFirstPartyHosts:
            rumConfig.urlSessionTracking = .init(
                firstPartyHostsTracing: .trace(
                    hosts: [
                        customGETResourceURL.host!
                    ],
                    sampleRate: 100
                )
            )
        case .delegateWithAdditionalFirstPartyHosts:
            rumConfig.urlSessionTracking = .init(
                firstPartyHostsTracing: .trace(hosts: [], sampleRate: 100) // hosts will be set through `DDURLSessionDelegate`
            )
        }
        RUM.enable(with: rumConfig)
    }
}
