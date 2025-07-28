/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogCore
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
public class DDDatadog: NSObject {
    // MARK: - Public

    @objc
    public static func initialize(
        configuration: DDConfiguration,
        trackingConsent: DDTrackingConsent
    ) {
        Datadog.initialize(
            with: configuration.sdkConfiguration,
            trackingConsent: trackingConsent.sdkConsent
        )
    }

    @objc
    public static func setVerbosityLevel(_ verbosityLevel: DDSDKVerbosityLevel) {
        switch verbosityLevel {
        case .debug: Datadog.verbosityLevel = .debug
        case .warn: Datadog.verbosityLevel = .warn
        case .error: Datadog.verbosityLevel = .error
        case .critical: Datadog.verbosityLevel = .critical
        case .none: Datadog.verbosityLevel = nil
        }
    }

    @objc
    public static func verbosityLevel() -> DDSDKVerbosityLevel {
        switch Datadog.verbosityLevel {
        case .debug: return .debug
        case .warn: return .warn
        case .error: return .error
        case .critical: return .critical
        case .none: return .none
        }
    }

    @objc
    public static func setUserInfo(userId: String, name: String? = nil, email: String? = nil, extraInfo: [String: Any] = [:]) {
        Datadog.setUserInfo(id: userId, name: name, email: email, extraInfo: extraInfo.dd.swiftAttributes)
    }

    @objc
    public static func clearUserInfo() {
        Datadog.clearUserInfo()
    }

    @objc
    @available(*, deprecated, message: "UserInfo id property is now mandatory.")
    public static func setUserInfo(id: String? = nil, name: String? = nil, email: String? = nil, extraInfo: [String: Any] = [:]) {
        Datadog.setUserInfo(id: id, name: name, email: email, extraInfo: extraInfo.dd.swiftAttributes)
    }

    @objc
    public static func addUserExtraInfo(_ extraInfo: [String: Any]) {
        Datadog.addUserExtraInfo(extraInfo.dd.swiftAttributes)
    }

    @objc
    public static func setAccountInfo(accountId: String, name: String? = nil, extraInfo: [String: Any] = [:]) {
        Datadog.setAccountInfo(id: accountId, name: name, extraInfo: extraInfo.dd.swiftAttributes)
    }

    @objc
    public static func addAccountExtraInfo(_ extraInfo: [String: Any]) {
        Datadog.addAccountExtraInfo(extraInfo.dd.swiftAttributes)
    }

    @objc
    public static func clearAccountInfo() {
        Datadog.clearAccountInfo()
    }

    @objc
    public static func setTrackingConsent(consent: DDTrackingConsent) {
        Datadog.set(trackingConsent: consent.sdkConsent)
    }

    @objc
    public static func isInitialized() -> Bool {
        return Datadog.isInitialized()
    }

    @objc
    public static func stopInstance() {
        Datadog.stopInstance()
    }

    @objc
    public static func clearAllData() {
        Datadog.clearAllData()
    }

#if DD_SDK_COMPILED_FOR_TESTING
    @objc
    public static func flushAndDeinitialize() {
        Datadog.flushAndDeinitialize()
    }
#endif
}
