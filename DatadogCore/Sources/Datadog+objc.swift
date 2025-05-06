/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(objc)
import DatadogInternal

@objc(DDTrackingConsent)
@objcMembers
@_spi(objc)
public class objc_TrackingConsent: NSObject {
    internal let sdkConsent: TrackingConsent

    internal init(sdkConsent: TrackingConsent) {
        self.sdkConsent = sdkConsent
    }

    // MARK: - Public

    public static func granted() -> objc_TrackingConsent { .init(sdkConsent: .granted) }

    public static func notGranted() -> objc_TrackingConsent { .init(sdkConsent: .notGranted) }

    public static func pending() -> objc_TrackingConsent { .init(sdkConsent: .pending) }
}

@objc(DDDatadog)
@objcMembers
@_spi(objc)
public class objc_Datadog: NSObject {
    // MARK: - Public

    public static func initialize(
        configuration: objc_Configuration,
        trackingConsent: objc_TrackingConsent
    ) {
        Datadog.initialize(
            with: configuration.sdkConfiguration,
            trackingConsent: trackingConsent.sdkConsent
        )
    }

    public static func setVerbosityLevel(_ verbosityLevel: objc_CoreLoggerLevel) {
        switch verbosityLevel {
        case .debug: Datadog.verbosityLevel = .debug
        case .warn: Datadog.verbosityLevel = .warn
        case .error: Datadog.verbosityLevel = .error
        case .critical: Datadog.verbosityLevel = .critical
        case .none: Datadog.verbosityLevel = nil
        }
    }

    public static func verbosityLevel() -> objc_CoreLoggerLevel {
        switch Datadog.verbosityLevel {
        case .debug: return .debug
        case .warn: return .warn
        case .error: return .error
        case .critical: return .critical
        case .none: return .none
        }
    }

    public static func setUserInfo(userId: String, name: String? = nil, email: String? = nil, extraInfo: [String: Any] = [:]) {
        Datadog.setUserInfo(id: userId, name: name, email: email, extraInfo: extraInfo.dd.swiftAttributes)
    }

    public static func addUserExtraInfo(_ extraInfo: [String: Any]) {
        Datadog.addUserExtraInfo(extraInfo.dd.swiftAttributes)
    }

    public static func setTrackingConsent(consent: objc_TrackingConsent) {
        Datadog.set(trackingConsent: consent.sdkConsent)
    }

    public static func isInitialized() -> Bool {
        return Datadog.isInitialized()
    }

    public static func stopInstance() {
        Datadog.stopInstance()
    }

    public static func clearAllData() {
        Datadog.clearAllData()
    }

#if DD_SDK_COMPILED_FOR_TESTING
    public static func flushAndDeinitialize() {
        Datadog.flushAndDeinitialize()
    }
#endif
}
