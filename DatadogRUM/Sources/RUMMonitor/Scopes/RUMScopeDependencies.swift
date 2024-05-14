/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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
        self.cpu = VitalCPUReader(telemetry: telemetry)
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
    let firstPartyHosts: FirstPartyHosts?
    let eventBuilder: RUMEventBuilder
    let rumUUIDGenerator: RUMUUIDGenerator
    let backtraceReporter: BacktraceReporting?
    /// Integration with CIApp tests. It contains the CIApp test context when active.
    let ciTest: RUMCITest?
    let syntheticsTest: RUMSyntheticsTest?
    let vitalsReaders: VitalsReaders?
    let onSessionStart: RUM.SessionListener?
    let viewCache: ViewCache
    /// The RUM context necessary for tracking fatal errors like Crashes or fatal App Hangs.
    let fatalErrorContext: FatalErrorContextNotifying
    /// Telemetry endpoint.
    let telemetry: Telemetry
    let sessionType: RUMSessionType

    init(
        featureScope: FeatureScope,
        rumApplicationID: String,
        sessionSampler: Sampler,
        trackBackgroundEvents: Bool,
        trackFrustrations: Bool,
        firstPartyHosts: FirstPartyHosts?,
        eventBuilder: RUMEventBuilder,
        rumUUIDGenerator: RUMUUIDGenerator,
        backtraceReporter: BacktraceReporting?,
        ciTest: RUMCITest?,
        syntheticsTest: RUMSyntheticsTest?,
        vitalsReaders: VitalsReaders?,
        onSessionStart: RUM.SessionListener?,
        viewCache: ViewCache,
        fatalErrorContext: FatalErrorContextNotifying
    ) {
        self.featureScope = featureScope
        self.rumApplicationID = rumApplicationID
        self.sessionSampler = sessionSampler
        self.trackBackgroundEvents = trackBackgroundEvents
        self.trackFrustrations = trackFrustrations
        self.firstPartyHosts = firstPartyHosts
        self.eventBuilder = eventBuilder
        self.rumUUIDGenerator = rumUUIDGenerator
        self.backtraceReporter = backtraceReporter
        self.ciTest = ciTest
        self.syntheticsTest = syntheticsTest
        self.vitalsReaders = vitalsReaders
        self.onSessionStart = onSessionStart
        self.viewCache = viewCache
        self.fatalErrorContext = fatalErrorContext
        self.telemetry = featureScope.telemetry

        if ciTest != nil {
            self.sessionType = .ciTest
        } else if syntheticsTest != nil {
            self.sessionType = .synthetics
        } else {
            self.sessionType = .user
        }
    }
}
