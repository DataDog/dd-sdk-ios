/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

internal final class RUMFeature: DatadogRemoteFeature, RUMSessionSamplerProvider {
    static var name: String { Feature.rum }

    let requestBuilder: FeatureRequestBuilder

    let messageReceiver: FeatureMessageReceiver

    let monitor: Monitor

    let instrumentation: RUMInstrumentation

    let configuration: RUM.Configuration

    let anonymousIdentifierManager: AnonymousIdentifierManaging

    /// Collects memory/CPU timeseries samples during the RUM session, if enabled. Retained here so it can be
    /// flushed alongside other instrumentation in `flush()`.
    let timeseriesCollector: TimeseriesCollecting?

    /// Used by WebViewTracking to obtain the RUM session sampler synchronously.
    @ReadWriteLock
    private(set) var rumSessionSampler: DeterministicSampler?

    /// Overrides the max file age.
    let performanceOverride: PerformancePresetOverride? = PerformancePresetOverride(
        maxFileAgeForRead: 24.hours // RUM intake can ingest events up to 24hrs old
    )

    @MainActor
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
            sampleRate: configuration.debugSDK ? 100 : configuration.sessionEndedSampleRate,
            tracksBackgroundEvents: configuration.trackBackgroundEvents,
            isUsingSceneLifecycle: configuration.bundle.object(forInfoDictionaryKey: "UIApplicationSceneManifest") != nil
        )
        let tnsPredicateType = configuration.networkSettledResourcePredicate.metricPredicateType
        let invPredicateType = configuration.nextViewActionPredicate?.metricPredicateType ?? .disabled

        let appStateManager = AppStateManager(
            featureScope: featureScope,
            processId: configuration.processID,
            syntheticsEnvironment: configuration.syntheticsEnvironment
        )

        let bundleType = BundleType(bundle: configuration.bundle)
        var watchdogTermination: WatchdogTerminationMonitor?
        if bundleType == .iOSApp,
            configuration.trackWatchdogTerminations {
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
                    dateProvider: configuration.dateProvider,
                    uuidGenerator: configuration.uuidGenerator
                )
            )
            watchdogTermination = monitor
        }

        var renderLoopObserver: RenderLoopObserver? = nil
        var accessibilityReader: AccessibilityReading? = nil

        let firstFrameReader = FirstFrameReader(dateProvider: configuration.dateProvider, mediaTimeProvider: configuration.mediaTimeProvider)

        #if !os(watchOS) && !os(macOS)
        if configuration.collectAccessibility {
             accessibilityReader = AccessibilityReader(notificationCenter: configuration.notificationCenter)
        }

        renderLoopObserver = DisplayLinker(
            notificationCenter: configuration.notificationCenter,
            frameInfoProviderFactory: configuration.frameInfoProviderFactory
        )
        #endif

        let distributedTracing: (FirstPartyHosts, SampleRate)? = {
            switch configuration.urlSessionTracking?.firstPartyHostsTracing {
            case let .trace(hosts, sampleRate, _):
                return (FirstPartyHosts(hosts), sampleRate)
            case let .traceWithHeaders(hostsWithHeaders, sampleRate, _):
                return (FirstPartyHosts(hostsWithHeaders), sampleRate)
            case .none:
                return nil
            }
        }()

        let onSessionUpdate: RUM.SessionUpdater = { [onSessionStart = configuration.onSessionStart, _rumSessionSampler] sessionScope in
            _rumSessionSampler.mutate { $0 = sessionScope?.sampler }
            if let sessionScope {
                let sessionID = sessionScope.sessionUUID.toRUMDataFormat
                let isDiscarded = !sessionScope.sampler.isSampled
                onSessionStart?(sessionID, isDiscarded)
            }
        }

        let vitalsReaders = configuration.vitalsUpdateFrequency.map {
            VitalsReaders(
                frequency: $0.timeInterval,
                notificationCenterProvider: .default,
                telemetry: core.telemetry
            )
        }

        let ciTest = configuration.ciTestExecutionID.map { RUMCITest(testExecutionId: $0) }
        let syntheticsTest: RUMSyntheticsTest? = {
            if let testId = configuration.syntheticsTestId,
               let resultId = configuration.syntheticsResultId {
                return RUMSyntheticsTest(injected: nil, resultId: resultId, testId: testId, syntheticsInfo: [:])
            } else {
                return nil
            }
        }()

        let sessionSampleRate = configuration.debugSDK ? 100 : configuration.sessionSampleRate

        let timeseriesCollector: TimeseriesCollecting? = configuration.timeseries.flatMap { timeseries -> TimeseriesCollecting? in
            let effectiveCollectTypes = timeseries.effectiveCollectTypes
            // An empty effective selection (explicit `[]`, or emptied by platform availability, e.g.
            // `collectTypes: [.cpu]` on watchOS) would run the sampling timer for the whole session
            // without ever producing events, so skip creating the collector entirely.
            guard !effectiveCollectTypes.isEmpty else {
                return nil
            }
            return TimeseriesSessionCollector(
                memoryReader: VitalMemoryReader(),
                featureScope: featureScope,
                collectTypes: effectiveCollectTypes,
                ciTest: ciTest,
                syntheticsTest: syntheticsTest,
                sessionSampleRate: Double(sessionSampleRate),
                now: { configuration.dateProvider.now },
                mediaTimeProvider: configuration.mediaTimeProvider
            )
        }

        let dependencies = RUMScopeDependencies(
            featureScope: featureScope,
            rumApplicationID: configuration.applicationID,
            samplingRate: sessionSampleRate,
            trackBackgroundEvents: configuration.trackBackgroundEvents,
            trackFrustrations: configuration.trackFrustrations,
            hasAppHangsEnabled: configuration.appHangThreshold != nil,
            firstPartyHosts: distributedTracing?.0,
            distributedTracingSampleRate: distributedTracing.map { configuration.debugSDK ? 100 : $0.1 },
            eventBuilder: RUMEventBuilder(
                eventsMapper: eventsMapper
            ),
            rumUUIDGenerator: configuration.uuidGenerator,
            backtraceReporter: core.backtraceReporter,
            ciTest: ciTest,
            syntheticsTest: syntheticsTest,
            renderLoopObserver: renderLoopObserver,
            firstFrameReader: firstFrameReader,
            viewHitchesReaderFactory: {
                configuration.trackSlowFrames
                ? ViewHitchesReader(hangThreshold: configuration.appHangThreshold)
                : nil
            },
            vitalsReaders: vitalsReaders,
            accessibilityReader: accessibilityReader,
            onSessionUpdate: onSessionUpdate,
            viewCache: ViewCache(dateProvider: configuration.dateProvider),
            fatalErrorContext: FatalErrorContextNotifier(messageBus: featureScope),
            sessionEndedMetric: sessionEndedMetric,
            viewEndedMetricFactory: {
                let viewEndedController = ViewEndedController(
                    telemetry: featureScope.telemetry,
                    sampleRate: configuration.debugSDK ? 100 : configuration.viewEndedSampleRate
                )
                viewEndedController.add(metric: ViewEndedMetric(tnsConfigPredicate: tnsPredicateType, invConfigPredicate: invPredicateType))

                if configuration.trackSlowFrames {
                    viewEndedController.add(
                        metric: ViewHitchesMetric(
                            maxCount: ViewHitchesReader.Constants.maxCollectedHitches,
                            slowFrameThreshold: Int64(ViewHitchesReader.Constants.hitchesMultiplier),
                            maxDuration: (configuration.appHangThreshold ?? ViewHitchesReader.Constants.frozenFrameThreshold).dd.toInt64Nanoseconds,
                            viewMinDuration: RUMViewScope.Constants.minimumTimeSpentForRates.dd.toInt64Nanoseconds
                        )
                    )
                }

                return viewEndedController
            },
            appStateManager: appStateManager,
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
            },
            sessionType: configuration.sessionTypeOverride.flatMap { RUMSessionType(rawValue: $0) },
            timeseriesCollector: timeseriesCollector
        )

        self.monitor = Monitor(
            dependencies: dependencies,
            dateProvider: configuration.dateProvider
        )

        timeseriesCollector?.activeContextReader = monitor
        self.timeseriesCollector = timeseriesCollector

        if let refreshRateVital = dependencies.vitalsReaders?.refreshRate as? RenderLoopReader {
            dependencies.renderLoopObserver?.register(refreshRateVital)
        }

        firstFrameReader.publish(to: monitor)
        dependencies.renderLoopObserver?.register(firstFrameReader)

        // Resolved on each hang rather than captured here, as Crash Reporting - which owns this setting - can be
        // enabled after RUM. A missing Crash Reporting Feature means backtrace generation is *unavailable* rather
        // than *disabled*, which the App Hangs monitor reports differently, hence the `true` default.
        let isAppHangBacktraceEnabled: @Sendable () -> Bool = { [weak core] in
            core?.feature(named: Feature.crashReporting, type: CrashReportingConfiguration.self)?
                .appHangBacktraceEnabled ?? true
        }

        #if os(macOS)
        let heatmapIdentifierStore = HeatmapIdentifierStore()
        //try core.register(heatmapIdentifierRegistry: heatmapIdentifierStore)

        self.instrumentation = RUMInstrumentation(
            featureScope: featureScope,
            ddKitRUMViewsPredicate: configuration.appKitViewsPredicate,
            ddKitRUMActionsPredicate: configuration.appKitActionsPredicate,
            swiftUIRUMViewsPredicate: configuration.swiftUIViewsPredicate,
            swiftUIRUMActionsPredicate: configuration.swiftUIActionsPredicate,
            trackScrollAndSwipeActions: configuration.featureFlags[.trackScrollAndSwipeActions, default: true],
            longTaskThreshold: configuration.longTaskThreshold,
            appHangThreshold: configuration.appHangThreshold,
            mainQueue: configuration.mainQueue,
            dateProvider: configuration.dateProvider,
            backtraceReporter: core.backtraceReporter,
            fatalErrorContext: dependencies.fatalErrorContext,
            processID: configuration.processID,
            notificationCenter: configuration.notificationCenter,
            bundleType: bundleType,
            watchdogTermination: watchdogTermination,
            memoryWarningMonitor: nil,
            uuidGenerator: configuration.uuidGenerator,
            heatmapIdentifierRegistry: heatmapIdentifierStore,
            isAppHangBacktraceEnabled: isAppHangBacktraceEnabled
        )
        #elseif os(watchOS)
        self.instrumentation = RUMInstrumentation(
            featureScope: featureScope,
            longTaskThreshold: configuration.longTaskThreshold,
            appHangThreshold: configuration.appHangThreshold,
            mainQueue: configuration.mainQueue,
            dateProvider: configuration.dateProvider,
            backtraceReporter: core.backtraceReporter,
            fatalErrorContext: dependencies.fatalErrorContext,
            processID: configuration.processID,
            notificationCenter: configuration.notificationCenter,
            bundleType: bundleType,
            watchdogTermination: watchdogTermination,
            memoryWarningMonitor: nil,
            uuidGenerator: configuration.uuidGenerator,
            isAppHangBacktraceEnabled: isAppHangBacktraceEnabled
        )
        #else
        var memoryWarningMonitor: MemoryWarningMonitor?
        if configuration.trackMemoryWarnings {
            let memoryWarningReporter = MemoryWarningReporter()
            memoryWarningMonitor = MemoryWarningMonitor(
                memoryWarningReporter: memoryWarningReporter,
                notificationCenter: configuration.notificationCenter
            )
        }

        let heatmapIdentifierStore = HeatmapIdentifierStore()
        try core.register(heatmapIdentifierRegistry: heatmapIdentifierStore)

        self.instrumentation = RUMInstrumentation(
            featureScope: featureScope,
            ddKitRUMViewsPredicate: configuration.uiKitViewsPredicate,
            ddKitRUMActionsPredicate: configuration.uiKitActionsPredicate,
            swiftUIRUMViewsPredicate: configuration.swiftUIViewsPredicate,
            swiftUIRUMActionsPredicate: configuration.swiftUIActionsPredicate,
            trackScrollAndSwipeActions: configuration.featureFlags[.trackScrollAndSwipeActions, default: true],
            longTaskThreshold: configuration.longTaskThreshold,
            appHangThreshold: configuration.appHangThreshold,
            mainQueue: configuration.mainQueue,
            dateProvider: configuration.dateProvider,
            backtraceReporter: core.backtraceReporter,
            fatalErrorContext: dependencies.fatalErrorContext,
            processID: configuration.processID,
            notificationCenter: configuration.notificationCenter,
            bundleType: bundleType,
            watchdogTermination: watchdogTermination,
            memoryWarningMonitor: memoryWarningMonitor,
            uuidGenerator: configuration.uuidGenerator,
            heatmapIdentifierRegistry: heatmapIdentifierStore,
            isAppHangBacktraceEnabled: isAppHangBacktraceEnabled
        )
        #endif
        self.requestBuilder = RequestBuilder(
            customIntakeURL: configuration.customEndpoint,
            eventsFilter: RUMViewEventsFilter(telemetry: core.telemetry),
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
            FlagEvaluationReceiver(monitor: monitor),
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
                        return RUMSyntheticsTest(injected: nil, resultId: resultId, testId: testId, syntheticsInfo: [:])
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

        if timeseriesCollector != nil {
            messageReceivers.append(HasReplayMessageReceiver(monitor: monitor))
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
        #if !os(watchOS)
        let swiftUIViewTrackingEnabled = configuration.swiftUIViewsPredicate != nil
        let swiftUIActionTrackingEnabled = configuration.swiftUIActionsPredicate != nil
        let trackNativeViews = configuration.ddKitViewsPredicate != nil
        let trackUserInteractions = configuration.ddKitActionsPredicate != nil
        #else
        let swiftUIViewTrackingEnabled = false
        let swiftUIActionTrackingEnabled = false
        let trackNativeViews = false
        let trackUserInteractions = false
        #endif

        let trackResourceHeaders: String? = {
            switch configuration.urlSessionTracking?.trackResourceHeaders {
            case .none, .disabled: return nil
            case .defaults: return "default_headers"
            case .custom: return "custom"
            }
        }()

        core.telemetry.configuration(
            appHangThreshold: configuration.appHangThreshold?.dd.toInt64Milliseconds,
            invTimeThresholdMs: configuration.nextViewActionPredicate?.invTimeThresholdMs,
            mobileVitalsUpdatePeriod: configuration.vitalsUpdateFrequency?.timeInterval.dd.toInt64Milliseconds,
            sessionSampleRate: Int64.ddWithNoOverflow(configuration.debugSDK ? 100 : configuration.sessionSampleRate),
            telemetrySampleRate: Int64.ddWithNoOverflow(configuration.debugSDK ? 100 : configuration.telemetrySampleRate),
            tnsTimeThresholdMs: configuration.networkSettledResourcePredicate.tnsTimeThresholdMs,
            traceSampleRate: configuration.urlSessionTracking?.firstPartyHostsTracing.map { Int64.ddWithNoOverflow($0.sampleRate) },
            swiftUIViewTrackingEnabled: swiftUIViewTrackingEnabled,
            swiftUIActionTrackingEnabled: swiftUIActionTrackingEnabled,
            trackBackgroundEvents: configuration.trackBackgroundEvents,
            trackFrustrations: configuration.trackFrustrations,
            trackLongTask: configuration.longTaskThreshold != nil,
            trackNativeLongTasks: configuration.longTaskThreshold != nil,
            trackNativeViews: trackNativeViews,
            trackNetworkRequests: configuration.urlSessionTracking != nil,
            trackResourceHeaders: trackResourceHeaders,
            trackUserInteractions: trackUserInteractions,
            useFirstPartyHosts: configuration.urlSessionTracking?.firstPartyHostsTracing != nil
        )

        // Manage anonymous identifier depending on the configuration.
        anonymousIdentifierManager.manageAnonymousIdentifier(shouldTrack: configuration.trackAnonymousUser)
    }
}

private extension NetworkSettledResourcePredicate {
    var tnsTimeThresholdMs: Int64? {
        switch self {
        case let timeBased as TimeBasedTNSResourcePredicate:
            return timeBased.threshold.dd.toInt64Milliseconds
        case let objcBridge as NetworkSettledResourcePredicateBridge:
            return (objcBridge.objcPredicate as? objc_TimeBasedTNSResourcePredicate)?
                .swiftPredicate.tnsTimeThresholdMs
        default:
            return nil
        }
    }
}

private extension NextViewActionPredicate {
    var invTimeThresholdMs: Int64? {
        switch self {
        case let timeBased as TimeBasedINVActionPredicate:
            return timeBased.maxTimeToNextView.dd.toInt64Milliseconds
        case let objcBridge as NextViewActionPredicateBridge:
            return (objcBridge.objcPredicate as? objc_TimeBasedINVActionPredicate)?
                .swiftPredicate.invTimeThresholdMs
        default:
            return nil
        }
    }
}

extension RUMFeature: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        instrumentation.appHangs?.flush()
        timeseriesCollector?.flush()
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
