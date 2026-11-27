/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

import Foundation
import DatadogInternal

// Keep native types out of the distributed Swift module interface.
@_implementationOnly import DatadogMachProfiler

/// Persists CPU and memory settings for the next process launch based on tracking consent.
internal final class ProfilingLaunchSettingsWriter: FeatureMessageReceiver {
    private let applicationLaunchSampleRate: SampleRate
    private let memorySampleRate: SampleRate
    private let userDefaults: UserDefaults //swiftlint:disable:this required_reason_api_name
    /// Accessed on the serial message bus after initialization.
    private var trackingConsent: TrackingConsent?

    init(
        applicationLaunchSampleRate: SampleRate,
        memorySampleRate: SampleRate,
        userDefaults: UserDefaults //swiftlint:disable:this required_reason_api_name
    ) {
        self.applicationLaunchSampleRate = applicationLaunchSampleRate
        self.memorySampleRate = memorySampleRate
        self.userDefaults = userDefaults
        // Core delivers the initial consent after registration.
        write(trackingConsent: .notGranted)
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        if case let .context(context) = message {
            write(trackingConsent: context.trackingConsent)
        }
        return false
    }

    private func write(trackingConsent: TrackingConsent) {
        guard self.trackingConsent != trackingConsent else {
            return
        }
        self.trackingConsent = trackingConsent
        let isEnabled = trackingConsent != .notGranted
        userDefaults.setValue(isEnabled, forKey: DD_PROFILING_IS_ENABLED_KEY)
        userDefaults.setValue(isEnabled ? applicationLaunchSampleRate : 0, forKey: DD_PROFILING_APP_LAUNCH_SAMPLE_RATE_KEY)
        userDefaults.setValue(isEnabled ? memorySampleRate : 0, forKey: DD_PROFILING_MEMORY_SAMPLE_RATE_KEY)
    }
}

#endif
