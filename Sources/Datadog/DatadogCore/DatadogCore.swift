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

/// A shim interface for allowing V1 Features generic initialization in `DatadogCore`.
internal protocol V1FeatureInitializable {
    /// The configuration specific to this Feature.
    /// In V2 this will likely become a part of the public interface for the Feature module.
    associatedtype Configuration

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: Configuration,
        commonDependencies: FeaturesCommonDependencies,
        telemetry: Telemetry?
    )
}

/// Core implementation of Datadog SDK.
///
/// The core provides a storage and upload mechanism for each registered Feature
/// based on their respective configuration.
///
/// By complying with `DatadogCoreProtocol`, the core can
/// provide context and writing scopes to Features for event recording.
internal final class DatadogCore {
    /// The root location for storing Features data in this instance of the SDK.
    /// Each Feature creates its own set of subdirectories in `rootDirectory` based on their storage configuration.
    let rootDirectory: Directory
    /// The configuration of SDK core.
    let configuration: CoreConfiguration
    /// A set of dependencies used by SDK core to power Features.
    let dependencies: CoreDependencies
    /// Telemetry monitor, if configured.
    var telemetry: Telemetry?

    private var v1Features: [String: Any] = [:]

    /// The SDK Context for V1.
    internal let v1Context: DatadogV1Context

    /// Creates a core instance.
    ///
    /// - Parameters:
    ///   - directory: the root directory for this instance of SDK.
    ///   - configuration: the configuration of SDK core.
    ///   - dependencies: a set of dependencies used by SDK core to power Features.
    init(
        rootDirectory: Directory,
        configuration: CoreConfiguration,
        dependencies: CoreDependencies
    ) {
        self.rootDirectory = rootDirectory
        self.configuration = configuration
        self.dependencies = dependencies
        self.v1Context = DatadogV1Context(configuration: configuration, dependencies: dependencies)
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

    /// Creates V1 Feature using its V2 configuration.
    ///
    /// `DatadogCore` uses its core `configuration` to inject feature-agnostic parts of V1 setup.
    /// Feature-specific part is provided explicitly with `featureSpecificConfiguration`.
    ///
    /// - Returns: an instance of V1 feature
    func create<Feature: V1FeatureInitializable>(
        storageConfiguration: FeatureStorageConfiguration,
        uploadConfiguration: FeatureUploadConfiguration,
        featureSpecificConfiguration: Feature.Configuration
    ) throws -> Feature {
        let v1Directories = try FeatureDirectories(
            sdkRootDirectory: rootDirectory,
            storageConfiguration: storageConfiguration
        )

        let storage = FeatureStorage(
            featureName: storageConfiguration.featureName,
            dataFormat: uploadConfiguration.payloadFormat,
            directories: v1Directories,
            commonDependencies: dependencies,
            telemetry: telemetry
        )

        let upload = FeatureUpload(
            featureName: uploadConfiguration.featureName,
            storage: storage,
            requestBuilder: uploadConfiguration.createRequestBuilder(v1Context, telemetry),
            commonDependencies: dependencies,
            telemetry: telemetry
        )

        return Feature(
            storage: storage,
            upload: upload,
            configuration: featureSpecificConfiguration,
            commonDependencies: dependencies,
            telemetry: telemetry
        )
    }

    func register<T>(feature instance: T?) {
        let key = String(describing: T.self)
        v1Features[key] = instance
    }

    func feature<T>(_ type: T.Type) -> T? {
        let key = String(describing: T.self)
        return v1Features[key] as? T
    }

    var context: Any {
        return v1Context
    }
}
