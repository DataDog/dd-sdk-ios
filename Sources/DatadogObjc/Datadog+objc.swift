/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog
import DatadogInternal

@objc
public class DDTrackingConsent: NSObject {
    internal let sdkConsent: TrackingConsent

    internal init(sdkConsent: TrackingConsent) {
        self.sdkConsent = sdkConsent
    }

    // MARK: - Public

    @objc
    public static func granted() -> DDTrackingConsent { .init(sdkConsent: .granted) }

    @objc
    public static func notGranted() -> DDTrackingConsent { .init(sdkConsent: .notGranted) }

    @objc
    public static func pending() -> DDTrackingConsent { .init(sdkConsent: .pending) }
}

@objc
public class DDCore: NSObject {
    // MARK: - Public

    @objc
    public static func initialize(
        configuration: DDConfiguration,
        trackingConsent: DDTrackingConsent
    ) {
        DatadogCore.initialize(
            with: configuration.sdkConfiguration,
            trackingConsent: trackingConsent.sdkConsent
        )
    }

    @objc
    public static func setVerbosityLevel(_ verbosityLevel: DDSDKVerbosityLevel) {
        switch verbosityLevel {
        case .debug: DatadogCore.verbosityLevel = .debug
        case .warn: DatadogCore.verbosityLevel = .warn
        case .error: DatadogCore.verbosityLevel = .error
        case .critical: DatadogCore.verbosityLevel = .critical
        case .none: DatadogCore.verbosityLevel = nil
        }
    }

    @objc
    public static func verbosityLevel() -> DDSDKVerbosityLevel {
        switch DatadogCore.verbosityLevel {
        case .debug: return .debug
        case .warn: return .warn
        case .error: return .error
        case .critical: return .critical
        case .none: return .none
        }
    }

    @objc
    public static func setUserInfo(id: String? = nil, name: String? = nil, email: String? = nil, extraInfo: [String: Any] = [:]) {
        DatadogCore.setUserInfo(id: id, name: name, email: email, extraInfo: castAttributesToSwift(extraInfo))
    }

    @objc
    public static func setTrackingConsent(consent: DDTrackingConsent) {
        DatadogCore.set(trackingConsent: consent.sdkConsent)
    }

    @objc
    public static func clearAllData() {
        DatadogCore.clearAllData()
    }

#if DD_SDK_COMPILED_FOR_TESTING
    @objc
    public static func flushAndDeinitialize() {
        DatadogCore.flushAndDeinitialize()
    }
#endif
}
