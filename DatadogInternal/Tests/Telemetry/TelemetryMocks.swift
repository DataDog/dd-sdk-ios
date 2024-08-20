/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import TestUtilities

@testable import DatadogInternal

extension ConfigurationTelemetry {
    static func mockRandom() -> Self {
        ConfigurationTelemetry(
            actionNameAttribute: .mockRandom(),
            allowFallbackToLocalStorage: .mockRandom(),
            allowUntrustedEvents: .mockRandom(),
            appHangThreshold: .mockRandom(),
            backgroundTasksEnabled: .mockRandom(),
            batchProcessingLevel: .mockRandom(),
            batchSize: .mockRandom(),
            batchUploadFrequency: .mockRandom(),
            dartVersion: .mockRandom(),
            defaultPrivacyLevel: .mockRandom(),
            forwardErrorsToLogs: .mockRandom(),
            initializationType: .mockRandom(),
            mobileVitalsUpdatePeriod: .mockRandom(),
            reactNativeVersion: .mockRandom(),
            reactVersion: .mockRandom(),
            sessionReplaySampleRate: .mockRandom(),
            sessionSampleRate: .mockRandom(),
            silentMultipleInit: .mockRandom(),
            startRecordingImmediately: .mockRandom(),
            startSessionReplayRecordingManually: .mockRandom(),
            telemetryConfigurationSampleRate: .mockRandom(),
            telemetrySampleRate: .mockRandom(),
            tracerAPI: .mockRandom(),
            tracerAPIVersion: .mockRandom(),
            traceSampleRate: .mockRandom(),
            trackBackgroundEvents: .mockRandom(),
            trackCrossPlatformLongTasks: .mockRandom(),
            trackErrors: .mockRandom(),
            trackFlutterPerformance: .mockRandom(),
            trackFrustrations: .mockRandom(),
            trackLongTask: .mockRandom(),
            trackNativeErrors: .mockRandom(),
            trackNativeLongTasks: .mockRandom(),
            trackNativeViews: .mockRandom(),
            trackNetworkRequests: .mockRandom(),
            trackResources: .mockRandom(),
            trackSessionAcrossSubdomains: .mockRandom(),
            trackUserInteractions: .mockRandom(),
            trackViewsManually: .mockRandom(),
            unityVersion: .mockRandom(),
            useAllowedTracingUrls: .mockRandom(),
            useBeforeSend: .mockRandom(),
            useExcludedActivityUrls: .mockRandom(),
            useFirstPartyHosts: .mockRandom(),
            useLocalEncryption: .mockRandom(),
            useProxy: .mockRandom(),
            useSecureSessionCookie: .mockRandom(),
            useTracing: .mockRandom(),
            useWorkerUrl: .mockRandom()
        )
    }
}
