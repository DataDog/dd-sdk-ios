/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Feature-agnostic SDK configuration.
internal typealias CoreConfiguration = FeaturesConfiguration.Common

/// Feature-agnostic set of dependencies powering Features storage, upload and event recording.
internal typealias CoreDependencies = FeaturesCommonDependencies

/// Core implementation of Datadog SDK.
///
/// The core provides a storage and upload mechanism for each registered Feature
/// based on their respective configuration.
///
/// By complying with `DatadogCoreProtocol`, the core can
/// provide context and writing scopes to Features for event recording.
internal final class DatadogCore {
    /// The configuration of SDK core.
    let configuration: CoreConfiguration
    /// A set of dependencies used by SDK core for powering Features.
    let dependencies: CoreDependencies

    private var v1Features: [String: Any] = [:]

    /// Creates a core instance.
    ///
    /// - Parameters:
    ///   - configuration: the configuration of SDK core.
    ///   - dependencies: a set of dependencies used by SDK core for powering Features.
    init(
        configuration: CoreConfiguration,
        dependencies: CoreDependencies
    ) {
        self.configuration = configuration
        self.dependencies = dependencies
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
        dependencies.userInfoProvider.value = UserInfo(
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
        dependencies.consentProvider.changeConsent(to: trackingConsent)
    }
}

extension DatadogCore: DatadogCoreProtocol {
    // MARK: - V1 interface

    func register<T>(feature instance: T?) {
        let key = String(describing: T.self)
        v1Features[key] = instance
    }

    func feature<T>(_ type: T.Type) -> T? {
        let key = String(describing: T.self)
        return v1Features[key] as? T
    }
}
