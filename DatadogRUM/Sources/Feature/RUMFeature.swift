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

    let telemetry: TelemetryCore

    convenience init(
        in core: DatadogCoreProtocol,
        configuration: RUM.Configuration
    ) throws {
        let dependencies = RUMScopeDependencies(
            core: core,
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
                eventsMapper: RUMEventsMapper(
                    viewEventMapper: configuration.viewEventMapper,
                    errorEventMapper: configuration.errorEventMapper,
                    resourceEventMapper: configuration.resourceEventMapper,
                    actionEventMapper: configuration.actionEventMapper,
                    longTaskEventMapper: configuration.longTaskEventMapper
                )
            ),
            rumUUIDGenerator: configuration.uuidGenerator,
            ciTest: configuration.ciTestExecutionID.map { RUMCITest(testExecutionId: $0) },
            vitalsReaders: configuration.vitalsUpdateFrequency.map { VitalsReaders(frequency: $0.timeInterval) },
            onSessionStart: configuration.onSessionStart
        )

        try self.init(
            in: core,
            configuration: configuration,
            with: Monitor(core: core, dependencies: dependencies, dateProvider: configuration.dateProvider)
        )
    }

    private init(
        in core: DatadogCoreProtocol,
        configuration: RUM.Configuration,
        with monitor: Monitor
    ) throws {
        self.monitor = monitor
        self.instrumentation = RUMInstrumentation(
            uiKitRUMViewsPredicate: configuration.uiKitViewsPredicate,
            uiKitRUMActionsPredicate: configuration.uiKitActionsPredicate,
            longTaskThreshold: configuration.longTaskThreshold,
            dateProvider: configuration.dateProvider
        )
        self.requestBuilder = RequestBuilder(
            customIntakeURL: configuration.customEndpoint,
            eventsFilter: RUMViewEventsFilter()
        )
        self.messageReceiver = CombinedFeatureMessageReceiver(
            TelemetryReceiver(
                dateProvider: configuration.dateProvider,
                sampler: Sampler(samplingRate: configuration.telemetrySampleRate),
                configurationExtraSampler: Sampler(samplingRate: configuration.configurationTelemetrySampleRate),
                metricsExtraSampler: Sampler(samplingRate: configuration.metricsTelemetrySampleRate)
            ),
            ErrorMessageReceiver(monitor: monitor),
            WebViewEventReceiver(
                dateProvider: configuration.dateProvider,
                commandSubscriber: monitor
            ),
            CrashReportReceiver(
                applicationID: configuration.applicationID,
                dateProvider: configuration.dateProvider,
                sessionSampler: Sampler(samplingRate: configuration.debugSDK ? 100 : configuration.sessionSampleRate),
                trackBackgroundEvents: configuration.trackBackgroundEvents,
                uuidGenerator: configuration.uuidGenerator,
                ciTest: configuration.ciTestExecutionID.map { RUMCITest(testExecutionId: $0) }
            )
        )
        self.telemetry = TelemetryCore(core: core)

        // Forward instrumentation calls to monitor:
        instrumentation.publish(to: monitor)

        // Send configuration telemetry:
        telemetry.configuration(
            mobileVitalsUpdatePeriod: configuration.vitalsUpdateFrequency?.timeInterval.toInt64Milliseconds,
            sessionSampleRate: Int64(withNoOverflow: configuration.sessionSampleRate),
            telemetrySampleRate: Int64(withNoOverflow: configuration.telemetrySampleRate),
            traceSampleRate: configuration.urlSessionTracking?.firstPartyHostsTracing.map { Int64(withNoOverflow: $0.sampleRate) },
            trackBackgroundEvents: configuration.trackBackgroundEvents,
            trackFrustrations: configuration.trackFrustrations,
            trackInteractions: configuration.uiKitActionsPredicate != nil,
            trackLongTask: configuration.longTaskThreshold != nil,
            trackNativeLongTasks: configuration.longTaskThreshold != nil,
            trackNativeViews: configuration.uiKitViewsPredicate != nil,
            trackNetworkRequests: configuration.urlSessionTracking != nil,
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
