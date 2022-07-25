/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if canImport(UIKit)
import UIKit
#endif

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

    private var v1Features: [String: Any] = [:]

    /// The SDK Context for V1.
    internal private(set) var v1Context: DatadogV1Context

    private let contextProvider: DatadogContextProvider
    private let userInfoPublisher = UserInfoPublisher()

    /// Creates a core instance.
    ///
    /// - Parameters:
    ///   - directory: The core directory for this instance of the SDK.
    ///   - configuration: The configuration of the SDK core.
    ///   - dependencies: A set of dependencies used by the SDK core to power Features.
    ///   - v1Context: The v1 context.
    ///   - contextProvider: The core context provider.
    init(
        directory: CoreDirectory,
        configuration: CoreConfiguration,
        dependencies: CoreDependencies,
        v1Context: DatadogV1Context,
        contextProvider: DatadogContextProvider
    ) {
        self.directory = directory
        self.configuration = configuration
        self.dependencies = dependencies
        self.v1Context = v1Context
        self.contextProvider = contextProvider
        self.contextProvider.subscribe(\.userInfo, to: userInfoPublisher)
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
        let userInfo = UserInfo(
            id: id,
            name: name,
            email: email,
            extraInfo: extraInfo
        )

        userInfoPublisher.current = userInfo
        dependencies.userInfoProvider.value = userInfo
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
        uploadConfiguration: FeatureV1UploadConfiguration,
        featureSpecificConfiguration: Feature.Configuration
    ) throws -> Feature {
        let featureDirectories = try directory.getFeatureDirectories(configuration: storageConfiguration)

        let storage = FeatureStorage(
            featureName: storageConfiguration.featureName,
            queue: readWriteQueue,
            directories: featureDirectories,
            commonDependencies: dependencies
        )

        let upload = FeatureUpload(
            featureName: uploadConfiguration.featureName,
            contextProvider: contextProvider,
            fileReader: storage.reader,
            requestBuilder: uploadConfiguration.requestBuilder,
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

    func scope<T>(for featureType: T.Type) -> FeatureV1Scope? {
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
internal struct DatadogCoreFeatureScope: FeatureV1Scope {
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

extension DatadogContextProvider {
    /// Extension to create a context provider based on v1 configuration and dependencies.
    ///
    /// This initiliazer is necessary while migrating to v2, but this will be move up to the
    /// configuration of the core SDK.
    ///
    /// - Parameters:
    ///   - configuration: v1 configuration
    ///   - dependencies: v1 dependencies.
    convenience init(configuration: CoreConfiguration, dependencies: CoreDependencies) {
        let context = DatadogContext(
            site: configuration.site,
            clientToken: configuration.clientToken,
            service: configuration.serviceName,
            env: configuration.environment,
            version: configuration.applicationVersion,
            source: configuration.source,
            sdkVersion: configuration.sdkVersion,
            ciAppOrigin: configuration.origin,
            serverTimeOffset: .zero,
            applicationName: configuration.applicationName,
            applicationBundleIdentifier: configuration.applicationBundleIdentifier,
            sdkInitDate: dependencies.sdkInitDate,
            device: dependencies.deviceInfo,
            isLowPowerModeEnabled: false
        )

        self.init(context: context)

        subscribe(\.serverTimeOffset, to: KronosClockPublisher())
        assign(reader: LaunchTimeReader(), to: \.launchTime)

        if #available(iOS 12, tvOS 12, *) {
            subscribe(\.networkConnectionInfo, to: NWPathMonitorPublisher())
        } else {
            assign(reader: SCNetworkReachabilityReader(), to: \.networkConnectionInfo)
        }

        #if os(iOS)
        if #available(iOS 12, *) {
            subscribe(\.carrierInfo, to: iOS12CarrierInfoPublisher())
        } else {
            assign(reader: iOS11CarrierInfoReader(), to: \.carrierInfo)
        }
        #endif

        #if os(iOS) && !targetEnvironment(simulator)
        assign(reader: BatteryStatusReader(), to: \.batteryStatus)
        #endif

        #if os(iOS) || os(tvOS)
        DispatchQueue.main.async {
            // must be call on the main thread to read `UIApplication.State`
            let applicationStatePublisher = ApplicationStatePublisher(dateProvider: dependencies.dateProvider)
            self.subscribe(\.applicationStateHistory, to: applicationStatePublisher)
        }
        #endif
    }
}
