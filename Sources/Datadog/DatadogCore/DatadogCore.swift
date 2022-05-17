/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Core implementation of Datadog SDK.
///
/// The core provides a storage and upload mechanism for each registered
/// feature based on their respective configuration.
///
/// By complying with `DatadogCoreProtocol`, the core can
/// provide context and writing scopes to features for event recording.
internal final class DatadogCore {
    /// The user tracking consent provider.
    let consentProvider: ConsentProvider

    /// User PII.
    let userInfoProvider: UserInfoProvider

    private var v1Features: [String: Any] = [:]

    /// Creates a core instance.
    ///
    /// - Parameters:
    ///   - consentProvider: The user tracking consent provider.
    ///   - userInfoProvider: User PII.
    init(
        consentProvider: ConsentProvider,
        userInfoProvider: UserInfoProvider
    ) {
        self.consentProvider = consentProvider
        self.userInfoProvider = userInfoProvider
    }

    /// Sets current user information.
    ///
    /// Those will be added to logs, traces and RUM events automatically.
    /// 
    /// - Parameters:
    ///   - id: User ID, if any
    ///   - name: Name representing the user, if any
    ///   - email: User's email, if any
    ///   - extraInfo: User's custom attributes, if any
    func setUserInfo(
        id: String? = nil,
        name: String? = nil,
        email: String? = nil,
        extraInfo: [AttributeKey: AttributeValue] = [:]
    ) {
        userInfoProvider.value = UserInfo(
            id: id,
            name: name,
            email: email,
            extraInfo: extraInfo
        )
    }

    /// Sets the tracking consent regarding the data collection for the Datadog SDK.
    /// 
    /// - Parameter trackingConsent: new consent value, which will be applied for all data collected from now on
    func set(trackingConsent: TrackingConsent) {
        consentProvider.changeConsent(to: trackingConsent)
    }
}

extension DatadogCore: DatadogCoreProtocol {
    func registerFeature(named featureName: String, storage: FeatureStorageConfiguration, upload: FeatureUploadConfiguration) {
        // no-op
    }

    func scope(forFeature featureName: String) -> FeatureScope? {
        // no-op
        return nil
    }

    // MARK: V1 interface

    func registerFeature(named featureName: String, instance: Any?) {
        v1Features[featureName] = instance
    }

    func feature<T>(_ type: T.Type, named featureName: String) -> T? {
        return v1Features[featureName] as? T
    }
}
