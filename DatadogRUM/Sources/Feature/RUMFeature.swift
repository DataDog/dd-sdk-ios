/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal
import UIKit

internal final class RUMFeature: DatadogRemoteFeature {
    static let name = "rum"

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver

    let monitor: Monitor

    let instrumentation: RUMInstrumentation

    let configuration: RUM.Configuration

    let anonymousIdentifierManager: AnonymousIdentifierManaging

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
        let sessionEndedMetric = SessionEndedMetricController(
            telemetry: core.telemetry,
            sampleRate: configuration.sessionEndedSampleRate
        )
        let tnsPredicateType = configuration.networkSettledResourcePredicate.metricPredicateType
        let invPredicateType = configuration.nextViewActionPredicate?.metricPredicateType ?? .disabled

        var watchdogTermination: WatchdogTerminationMonitor?
        if configuration.trackWatchdogTerminations {
            let appStateManager = WatchdogTerminationAppStateManager(
                featureScope: featureScope,
                processId: configuration.processID,
                syntheticsEnvironment: configuration.syntheticsEnvironment
            )
            let monitor = WatchdogTerminationMonitor(
                appStateManager: appStateManager,
                checker: .init(
                    appStateManager: appStateManager,
                    featureScope: featureScope
                ),
                storage: core.storage,
                feature: featureScope,
                reporter: WatchdogTerminationReporter(
                    featureScope: featureScope,
                    dateProvider: configuration.dateProvider
                )
            )
            watchdogTermination = monitor
        }

        let dependencies = RUMScopeDependencies(
            featureScope: featureScope,
            rumApplicationID: configuration.applicationID,
            sessionSampler: Sampler(samplingRate: configuration.debugSDK ? 100 : configuration.sessionSampleRate),
            trackBackgroundEvents: configuration.trackBackgroundEvents,
            trackFrustrations: configuration.trackFrustrations,
            hasAppHangsEnabled: configuration.appHangThreshold != nil,
            firstPartyHosts: {
                switch configuration.urlSessionTracking?.firstPartyHostsTracing {
                case let .trace(hosts, _, _):
                    return FirstPartyHosts(hosts)
                case let .traceWithHeaders(hostsWithHeaders, _, _):
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
                if let testId = configuration.syntheticsTestId,
                   let resultId = configuration.syntheticsResultId {
                    return RUMSyntheticsTest(injected: nil, resultId: resultId, testId: testId)
                } else {
                    return nil
                }
            }(),
            renderLoopObserver: DisplayLinker(notificationCenter: configuration.notificationCenter),
            viewHitchesReaderFactory: {
                configuration.featureFlags[.viewHitches]
                ? ViewHitchesReader(hangThreshold: configuration.appHangThreshold)
                : nil
            },
            vitalsReaders: configuration.vitalsUpdateFrequency.map {
                VitalsReaders(
                    frequency: $0.timeInterval,
                    telemetry: core.telemetry
                )
            },
            onSessionStart: configuration.onSessionStart,
            viewCache: ViewCache(dateProvider: configuration.dateProvider),
            fatalErrorContext: FatalErrorContextNotifier(messageBus: featureScope),
            sessionEndedMetric: sessionEndedMetric,
            viewEndedMetricFactory: {
                let viewEndedController = ViewEndedController(
                    telemetry: featureScope.telemetry,
                    sampleRate: configuration.viewEndedSampleRate
                )
                viewEndedController.add(metric: ViewEndedMetric(tnsConfigPredicate: tnsPredicateType, invConfigPredicate: invPredicateType))

                if configuration.featureFlags[.viewHitches] {
                    viewEndedController.add(
                        metric: ViewHitchesMetric(
                            maxCount: ViewHitchesReader.Constants.maxCollectedHitches,
                            slowFrameThreshold: Int64(ViewHitchesReader.Constants.hitchesMultiplier),
                            maxDuration: (configuration.appHangThreshold ?? ViewHitchesReader.Constants.frozenFrameThreshold).toInt64Nanoseconds,
                            viewMinDuration: RUMViewScope.Constants.minimumTimeSpentForRates.toInt64Nanoseconds
                        )
                    )
                }

                return viewEndedController
            },
            watchdogTermination: watchdogTermination,
            networkSettledMetricFactory: { viewStartDate, viewName in
                return TNSMetric(
                    viewName: viewName,
                    viewStartDate: viewStartDate,
                    resourcePredicate: configuration.networkSettledResourcePredicate
                )
            },
            interactionToNextViewMetricFactory: {
                guard let nextViewActionPredicate = configuration.nextViewActionPredicate else {
                    return nil
                }
                return INVMetric(
                    predicate: nextViewActionPredicate
                )
            }
        )

        self.monitor = Monitor(
            dependencies: dependencies,
            dateProvider: configuration.dateProvider
        )

        if let refreshRateVital = dependencies.vitalsReaders?.refreshRate as? RenderLoopReader {
            dependencies.renderLoopObserver?.register(refreshRateVital)
        }

        let memoryWarningReporter = MemoryWarningReporter()
        let memoryWarningMonitor = MemoryWarningMonitor(
            backtraceReporter: core.backtraceReporter,
            memoryWarningReporter: memoryWarningReporter,
            notificationCenter: configuration.notificationCenter
        )

        self.instrumentation = RUMInstrumentation(
            featureScope: featureScope,
            uiKitRUMViewsPredicate: configuration.uiKitViewsPredicate,
            uiKitRUMActionsPredicate: configuration.uiKitActionsPredicate,
            swiftUIRUMViewsPredicate: configuration.swiftUIViewsPredicate,
            longTaskThreshold: configuration.longTaskThreshold,
            appHangThreshold: configuration.appHangThreshold,
            mainQueue: configuration.mainQueue,
            dateProvider: configuration.dateProvider,
            backtraceReporter: core.backtraceReporter,
            fatalErrorContext: dependencies.fatalErrorContext,
            processID: configuration.processID,
            notificationCenter: configuration.notificationCenter,
            watchdogTermination: watchdogTermination,
            memoryWarningMonitor: memoryWarningMonitor
        )
        self.requestBuilder = RequestBuilder(
            customIntakeURL: configuration.customEndpoint,
            eventsFilter: RUMViewEventsFilter(),
            telemetry: core.telemetry
        )
        var messageReceivers: [FeatureMessageReceiver] = [
            TelemetryInterceptor(sessionEndedMetric: sessionEndedMetric),
            TelemetryReceiver(
                featureScope: featureScope,
                dateProvider: configuration.dateProvider,
                sampler: Sampler(samplingRate: configuration.telemetrySampleRate),
                configurationExtraSampler: Sampler(samplingRate: configuration.configurationTelemetrySampleRate)
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
        ]

        if let watchdogTermination = watchdogTermination {
            messageReceivers.append(watchdogTermination)
        }

        self.messageReceiver = CombinedFeatureMessageReceiver(messageReceivers)

        // Forward instrumentation calls to monitor:
        instrumentation.publish(to: monitor)

        // Initialize anonymous identifier manager
        self.anonymousIdentifierManager = AnonymousIdentifierManager(
            featureScope: dependencies.featureScope,
            uuidGenerator: dependencies.rumUUIDGenerator
        )

        // Send configuration telemetry:

        core.telemetry.configuration(
            appHangThreshold: configuration.appHangThreshold?.toInt64Milliseconds,
            invTimeThresholdMs: (configuration.nextViewActionPredicate as? TimeBasedINVActionPredicate)?.maxTimeToNextView.toInt64Milliseconds,
            mobileVitalsUpdatePeriod: configuration.vitalsUpdateFrequency?.timeInterval.toInt64Milliseconds,
            sessionSampleRate: Int64(withNoOverflow: configuration.sessionSampleRate),
            telemetrySampleRate: Int64(withNoOverflow: configuration.telemetrySampleRate),
            tnsTimeThresholdMs: (configuration.networkSettledResourcePredicate as? TimeBasedTNSResourcePredicate)?.threshold.toInt64Milliseconds,
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

        // Manage anonymous identifier depending on the configuration.
        anonymousIdentifierManager.manageAnonymousIdentifier(shouldTrack: configuration.trackAnonymousUser)
    }
}

extension RUMFeature: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        instrumentation.appHangs?.flush()
    }
}

private extension RUM.Configuration.URLSessionTracking.FirstPartyHostsTracing {
    var sampleRate: SampleRate {
        switch self {
        case .trace(_, let sampleRate, _): return sampleRate
        case .traceWithHeaders(_, let sampleRate, _): return sampleRate
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
