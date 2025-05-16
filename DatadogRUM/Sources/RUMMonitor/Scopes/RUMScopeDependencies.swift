/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

internal struct VitalsReaders {
    let frequency: TimeInterval

    var cpu: SamplingBasedVitalReader
    var memory: SamplingBasedVitalReader
    var refreshRate: ContinuousVitalReader

    init(
        frequency: TimeInterval,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.frequency = frequency
        self.cpu = VitalCPUReader(notificationCenter: .default, telemetry: telemetry)
        self.memory = VitalMemoryReader()
        self.refreshRate = VitalRefreshRateReader()
    }
}

/// Dependency container for injecting components to `RUMScopes` hierarchy.
internal struct RUMScopeDependencies {
    /// The RUM feature scope to interact with core.
    let featureScope: FeatureScope
    let rumApplicationID: String
    let sessionSampler: Sampler
    let trackBackgroundEvents: Bool
    let trackFrustrations: Bool
    let hasAppHangsEnabled: Bool
    let firstPartyHosts: FirstPartyHosts?
    let eventBuilder: RUMEventBuilder
    let rumUUIDGenerator: RUMUUIDGenerator
    let backtraceReporter: BacktraceReporting?
    /// Integration with CIApp tests. It contains the CIApp test context when active.
    let ciTest: RUMCITest?
    let syntheticsTest: RUMSyntheticsTest?
    let renderLoopObserver: RenderLoopObserver?
    let viewHitchesReaderFactory: () -> (RenderLoopReader & ViewHitchesModel)?
    let vitalsReaders: VitalsReaders?
    let onSessionStart: RUM.SessionListener?
    let viewCache: ViewCache
    /// The RUM context necessary for tracking fatal errors like Crashes or fatal App Hangs.
    let fatalErrorContext: FatalErrorContextNotifying
    /// Telemetry endpoint.
    let telemetry: Telemetry
    let sessionType: RUMSessionType
    let sessionEndedMetric: SessionEndedMetricController
    let watchdogTermination: WatchdogTerminationMonitor?
    /// The accessibility state reader
    let accessibilityReader: AccessibilityReader

    /// A factory function that creates `ViewEndedMetricController` for each new view started.
    let viewEndedMetricFactory: () -> ViewEndedController

    /// A factory function that creates a `TNSMetric` for the given view start date.
    /// - Parameters:
    ///   - Date: The time when the view becomes visible (device time, no NTP offset).
    ///   - String: The name of the view.
    let networkSettledMetricFactory: (Date, String) -> TNSMetricTracking

    /// A factory function that creates a `INVMetric` when session starts.
    let interactionToNextViewMetricFactory: () -> INVMetricTracking?

    init(
        featureScope: FeatureScope,
        rumApplicationID: String,
        sessionSampler: Sampler,
        trackBackgroundEvents: Bool,
        trackFrustrations: Bool,
        hasAppHangsEnabled: Bool,
        firstPartyHosts: FirstPartyHosts?,
        eventBuilder: RUMEventBuilder,
        rumUUIDGenerator: RUMUUIDGenerator,
        backtraceReporter: BacktraceReporting?,
        ciTest: RUMCITest?,
        syntheticsTest: RUMSyntheticsTest?,
        renderLoopObserver: RenderLoopObserver?,
        viewHitchesReaderFactory: @escaping () -> (ViewHitchesModel & RenderLoopReader)?,
        vitalsReaders: VitalsReaders?,
        onSessionStart: RUM.SessionListener?,
        viewCache: ViewCache,
        fatalErrorContext: FatalErrorContextNotifying,
        sessionEndedMetric: SessionEndedMetricController,
        viewEndedMetricFactory: @escaping () -> ViewEndedController,
        watchdogTermination: WatchdogTerminationMonitor?,
        networkSettledMetricFactory: @escaping (Date, String) -> TNSMetricTracking,
        interactionToNextViewMetricFactory: @escaping () -> INVMetricTracking?,
        accessibilityReader: AccessibilityReader = AccessibilityReader()
    ) {
        self.featureScope = featureScope
        self.rumApplicationID = rumApplicationID
        self.sessionSampler = sessionSampler
        self.trackBackgroundEvents = trackBackgroundEvents
        self.trackFrustrations = trackFrustrations
        self.hasAppHangsEnabled = hasAppHangsEnabled
        self.firstPartyHosts = firstPartyHosts
        self.eventBuilder = eventBuilder
        self.rumUUIDGenerator = rumUUIDGenerator
        self.backtraceReporter = backtraceReporter
        self.ciTest = ciTest
        self.syntheticsTest = syntheticsTest
        self.renderLoopObserver = renderLoopObserver
        self.viewHitchesReaderFactory = viewHitchesReaderFactory
        self.vitalsReaders = vitalsReaders
        self.onSessionStart = onSessionStart
        self.viewCache = viewCache
        self.fatalErrorContext = fatalErrorContext
        self.telemetry = featureScope.telemetry
        self.sessionEndedMetric = sessionEndedMetric
        self.viewEndedMetricFactory = viewEndedMetricFactory
        self.watchdogTermination = watchdogTermination
        self.networkSettledMetricFactory = networkSettledMetricFactory
        self.interactionToNextViewMetricFactory = interactionToNextViewMetricFactory
        self.accessibilityReader = accessibilityReader

        if ciTest != nil {
            self.sessionType = .ciTest
        } else if syntheticsTest != nil {
            self.sessionType = .synthetics
        } else {
            self.sessionType = .user
        }
    }
}
