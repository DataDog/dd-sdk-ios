/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class RUMFeature: DatadogRemoteFeature {
    static let name = "rum"

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver

    let monitor: Monitor

    let instrumentation: RUMInstrumentation

    let configuration: RUM.Configuration

    init(
        in core: DatadogCoreProtocol,
        configuration: RUM.Configuration
    ) throws {
        self.configuration = configuration
        let eventsMapper = RUMEventsMapper(
            viewEventMapper: configuration.viewEventMapper,
            errorEventMapper: configuration.errorEventMapper,
            resourceEventMapper: configuration.resourceEventMapper,
            actionEventMapper: configuration.actionEventMapper,
            longTaskEventMapper: configuration.longTaskEventMapper,
            telemetry: core.telemetry
        )

        let featureScope = core.scope(for: RUMFeature.self)
        let dependencies = RUMScopeDependencies(
            featureScope: featureScope,
            rumApplicationID: configuration.applicationID,
            sessionSampler: Sampler(samplingRate: configuration.debugSDK ? 100 : configuration.sessionSampleRate),
            trackBackgroundEvents: configuration.trackBackgroundEvents,
            trackFrustrations: configuration.trackFrustrations,
            firstPartyHosts: {
                switch configuration.urlSessionTracking?.firstPartyHostsTracing {
                case let .trace(hosts, _):
                    return FirstPartyHosts(hosts)
                case let .traceWithHeaders(hostsWithHeaders, _):
                    return FirstPartyHosts(hostsWithHeaders)
                case .none:
                    return nil
                }
            }(),
            eventBuilder: RUMEventBuilder(
                eventsMapper: eventsMapper
            ),
            rumUUIDGenerator: configuration.uuidGenerator,
            backtraceReporter: core.backtraceReporter,
            ciTest: configuration.ciTestExecutionID.map { RUMCITest(testExecutionId: $0) },
            syntheticsTest: {
                if let testId = configuration.syntheticsTestId, let resultId = configuration.syntheticsResultId {
                    return RUMSyntheticsTest(injected: nil, resultId: resultId, testId: testId)
                } else {
                    return nil
                }
            }(),
            vitalsReaders: configuration.vitalsUpdateFrequency.map {
                VitalsReaders(
                    frequency: $0.timeInterval,
                    telemetry: core.telemetry
                )
            },
            onSessionStart: configuration.onSessionStart,
            viewCache: ViewCache()
        )

        self.monitor = Monitor(
            dependencies: dependencies,
            dateProvider: configuration.dateProvider
        )

        self.instrumentation = RUMInstrumentation(
            featureScope: featureScope,
            uiKitRUMViewsPredicate: configuration.uiKitViewsPredicate,
            uiKitRUMActionsPredicate: configuration.uiKitActionsPredicate,
            longTaskThreshold: configuration.longTaskThreshold,
            appHangThreshold: configuration.appHangThreshold,
            mainQueue: configuration.mainQueue,
            dateProvider: configuration.dateProvider,
            backtraceReporter: core.backtraceReporter,
            fatalErrorContext: dependencies.fatalErrorContext,
            processID: configuration.processID
        )
        self.requestBuilder = RequestBuilder(
            customIntakeURL: configuration.customEndpoint,
            eventsFilter: RUMViewEventsFilter(),
            telemetry: core.telemetry
        )
        self.messageReceiver = CombinedFeatureMessageReceiver(
            TelemetryReceiver(
                featureScope: featureScope,
                dateProvider: configuration.dateProvider,
                sampler: Sampler(samplingRate: configuration.telemetrySampleRate),
                configurationExtraSampler: Sampler(samplingRate: configuration.configurationTelemetrySampleRate),
                metricsExtraSampler: Sampler(samplingRate: configuration.metricsTelemetrySampleRate)
            ),
            ErrorMessageReceiver(
                featureScope: featureScope,
                monitor: monitor
            ),
            WebViewEventReceiver(
                featureScope: featureScope,
                dateProvider: configuration.dateProvider,
                commandSubscriber: monitor,
                viewCache: dependencies.viewCache
            ),
            CrashReportReceiver(
                featureScope: featureScope,
                applicationID: configuration.applicationID,
                dateProvider: configuration.dateProvider,
                sessionSampler: Sampler(samplingRate: configuration.debugSDK ? 100 : configuration.sessionSampleRate),
                trackBackgroundEvents: configuration.trackBackgroundEvents,
                uuidGenerator: configuration.uuidGenerator,
                ciTest: configuration.ciTestExecutionID.map { RUMCITest(testExecutionId: $0) },
                syntheticsTest: {
                    if let testId = configuration.syntheticsTestId, let resultId = configuration.syntheticsResultId {
                        return RUMSyntheticsTest(injected: nil, resultId: resultId, testId: testId)
                    } else {
                        return nil
                    }
                }(),
                eventsMapper: eventsMapper
            )
        )

        // Forward instrumentation calls to monitor:
        instrumentation.publish(to: monitor)

        // Send configuration telemetry:
        core.telemetry.configuration(
            appHangThreshold: configuration.appHangThreshold?.toInt64Milliseconds,
            mobileVitalsUpdatePeriod: configuration.vitalsUpdateFrequency?.timeInterval.toInt64Milliseconds,
            sessionSampleRate: Int64(withNoOverflow: configuration.sessionSampleRate),
            telemetrySampleRate: Int64(withNoOverflow: configuration.telemetrySampleRate),
            traceSampleRate: configuration.urlSessionTracking?.firstPartyHostsTracing.map { Int64(withNoOverflow: $0.sampleRate) },
            trackBackgroundEvents: configuration.trackBackgroundEvents,
            trackFrustrations: configuration.trackFrustrations,
            trackLongTask: configuration.longTaskThreshold != nil,
            trackNativeLongTasks: configuration.longTaskThreshold != nil,
            trackNativeViews: configuration.uiKitViewsPredicate != nil,
            trackNetworkRequests: configuration.urlSessionTracking != nil,
            trackUserInteractions: configuration.uiKitActionsPredicate != nil,
            useFirstPartyHosts: configuration.urlSessionTracking?.firstPartyHostsTracing != nil
        )
    }
}

extension RUMFeature: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        monitor.flush()
    }
}

private extension RUM.Configuration.URLSessionTracking.FirstPartyHostsTracing {
    var sampleRate: Float {
        switch self {
        case .trace(_, let sampleRate): return sampleRate
        case .traceWithHeaders(_, let sampleRate): return sampleRate
        }
    }
}

private extension RUM.Configuration.VitalsFrequency {
    var timeInterval: TimeInterval {
        switch self {
        case .frequent: return 0.1
        case .average:  return 0.5
        case .rare:     return 1
        }
    }
}
