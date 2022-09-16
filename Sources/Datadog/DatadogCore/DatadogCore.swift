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
        configuration: Configuration
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
    /// For each Feature a set of subdirectories is created inside `CoreDirectory` based on their storage configuration.
    let directory: CoreDirectory
    /// The configuration of SDK core.
    let configuration: CoreConfiguration
    /// A set of dependencies used by SDK core to power Features.
    let dependencies: CoreDependencies

    let readWriteQueue = DispatchQueue(
        label: "com.datadoghq.ios-sdk-read-write",
        target: .global(qos: .utility)
    )

    /// The app version provider.
    let appVersionProvider: AppVersionProvider

    private var v1Features: [String: Any] = [:]

    /// The SDK Context for V1.
    internal private(set) var v1Context: DatadogV1Context

    /// Creates a core instance.
    ///
    /// - Parameters:
    ///   - directory: the core directory for this instance of the SDK.
    ///   - configuration: the configuration of the SDK core.
    ///   - dependencies: a set of dependencies used by the SDK core to power Features.
    ///   - appVersionProvider: The app version provider.
    init(
        directory: CoreDirectory,
        configuration: CoreConfiguration,
        dependencies: CoreDependencies,
        appVersionProvider: AppVersionProvider
    ) {
        self.directory = directory
        self.configuration = configuration
        self.dependencies = dependencies
        self.appVersionProvider = appVersionProvider
        self.v1Context = DatadogV1Context(configuration: configuration, dependencies: dependencies, appVersionProvider: appVersionProvider)
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

extension DatadogCore: DatadogV1CoreProtocol {
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
        let featureDirectories = try directory.getFeatureDirectories(configuration: storageConfiguration)

        let storage = FeatureStorage(
            featureName: storageConfiguration.featureName,
            queue: readWriteQueue,
            dataFormat: uploadConfiguration.payloadFormat,
            directories: featureDirectories,
            commonDependencies: dependencies
        )

        let upload = FeatureUpload(
            featureName: uploadConfiguration.featureName,
            storage: storage,
            requestBuilder: uploadConfiguration.createRequestBuilder(v1Context),
            commonDependencies: dependencies
        )

        return Feature(
            storage: storage,
            upload: upload,
            configuration: featureSpecificConfiguration
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

    func scope<T>(for featureType: T.Type) -> V1FeatureScope? {
        let key = String(describing: T.self)

        guard let feature = v1Features[key] as? V1Feature else {
            return nil
        }

        return DatadogCoreFeatureScope(
            context: v1Context,
            storage: feature.storage
        )
    }

    var context: DatadogV1Context? {
        return v1Context
    }
}

/// A v1 Feature with an associated stroage.
internal protocol V1Feature {
    /// The feature's storage.
    var storage: FeatureStorage { get }
}

/// This Scope complies with `V1FeatureScope` to provide context and writer to
/// v1 Features.
///
/// The execution block is currently running in `sync`, this will change once the
/// context is provided on it's own queue.
internal struct DatadogCoreFeatureScope: V1FeatureScope {
    let context: DatadogV1Context
    let storage: FeatureStorage

    func eventWriteContext(_ block: (DatadogV1Context, Writer) throws -> Void) {
        do {
            try block(context, storage.writer)
        } catch {
            DD.telemetry.error("Failed to execute feature scope", error: error)
        }
    }
}
