/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Feature-agnostic SDK configuration.
internal typealias CoreConfiguration = FeaturesConfiguration.Common

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

    /// The storage r/w GDC queue.
    let readWriteQueue = DispatchQueue(
        label: "com.datadoghq.ios-sdk-read-write",
        target: .global(qos: .utility)
    )

    /// The message bus GDC queue.
    let messageBusQueue = DispatchQueue(
        label: "com.datadoghq.ios-sdk-message-bus",
        target: .global(qos: .utility)
    )

    /// The system date provider.
    let dateProvider: DateProvider

    /// The user consent provider.
    let consentProvider: ConsentProvider

    /// The user info provider that provide values to the
    /// `v1Context`.
    let userInfoProvider: UserInfoProvider

    /// The core SDK performance presets.
    let performance: PerformancePreset

    /// The HTTP Client for uploads.
    let httpClient: HTTPClient

    /// The on-disk data encryption.
    let encryption: DataEncryption?

    /// The user info publisher that publishes value to the
    /// `contextProvider`
    let userInfoPublisher = UserInfoPublisher()

    let featureAttributesPublisher = FeatureAttributesPublisher()

    /// The message bus used to dispatch messages to registered features.
    private var messageBus: [FeatureMessageReceiver] = []

    /// Registery for v1 features.
    private var v1Features: [String: Any] = [:]

    /// The SDK Context for V1.
    internal private(set) var v1Context: DatadogV1Context

    /// The core context provider.
    internal let contextProvider: DatadogContextProvider

    /// Creates a core instance.
    ///
    /// - Parameters:
    ///   - directory: The core directory for this instance of the SDK.
    ///   - dateProvider: The system date provider.
    ///   - consentProvider: The user consent provider.
    ///   - userInfoProvider: The user info provider.
    ///   - performance: The core SDK performance presets.
    ///   - httpClient: The HTTP Client for uploads.
    ///   - encryption: The on-disk data encryption.
    ///   - v1Context: The v1 context.
    ///   - contextProvider: The core context provider.
    init(
        directory: CoreDirectory,
        dateProvider: DateProvider,
        consentProvider: ConsentProvider,
        userInfoProvider: UserInfoProvider,
    	performance: PerformancePreset,
    	httpClient: HTTPClient,
    	encryption: DataEncryption?,
        v1Context: DatadogV1Context,
        contextProvider: DatadogContextProvider
    ) {
        self.directory = directory
        self.dateProvider = dateProvider
        self.consentProvider = consentProvider
        self.userInfoProvider = userInfoProvider
        self.performance = performance
        self.httpClient = httpClient
        self.encryption = encryption
        self.v1Context = v1Context
        self.contextProvider = contextProvider
        self.contextProvider.subscribe(\.userInfo, to: userInfoPublisher)
        self.contextProvider.subscribe(\.featuresAttributes, to: featureAttributesPublisher)
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
        userInfoProvider.value = userInfo
    }

    /// Sets the tracking consent regarding the data collection for the Datadog SDK.
    /// 
    /// - Parameter trackingConsent: new consent value, which will be applied for all data collected from now on
    func set(trackingConsent: TrackingConsent) {
        consentProvider.changeConsent(to: trackingConsent)
    }
}

extension DatadogCore: DatadogCoreProtocol {
    /* public */ func set(feature: String, attributes: FeatureMessageAttributes) {
        v1Context.featuresAttributesProvider.attributes[feature] = attributes
        featureAttributesPublisher.attributes[feature] = attributes
    }

    /* public */ func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        messageBusQueue.async {
            let receivers = self.messageBus.filter {
                $0.receive(message: message, from: self)
            }

            if receivers.isEmpty {
                fallback()
            }
        }
    }
}

extension DatadogCore: DatadogV1CoreProtocol {
    // MARK: - V1 interface

    func register<T>(feature instance: T?) {
        let key = String(describing: T.self)
        v1Features[key] = instance

        let messageBus = self.v1Features.values
            .compactMap { $0 as? V1Feature }
            .map(\.messageReceiver)

        messageBusQueue.async {
            // add/replace v1 feature to the message bus
            self.messageBus = messageBus
        }
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

    /// Creates V1 Feature using its V2 configuration.
    ///
    /// `DatadogCore` uses its core `configuration` to inject feature-agnostic parts of V1 setup.
    /// Feature-specific part is provided explicitly with `featureSpecificConfiguration`.
    ///
    /// - Parameters:
    ///   - configuration: The generic feature configuration.
    ///   - featureSpecificConfiguration: The feature-specific configuration.
    /// - Returns: an instance of V1 feature
    func create<Feature: V1FeatureInitializable>(
        configuration: DatadogFeatureConfiguration,
        featureSpecificConfiguration: Feature.Configuration
    ) throws -> Feature {
        let featureDirectories = try directory.getFeatureDirectories(forFeatureNamed: configuration.name)

        let storage = FeatureStorage(
            featureName: configuration.name,
            queue: readWriteQueue,
            directories: featureDirectories,
            dateProvider: dateProvider,
            consentProvider: consentProvider,
            performance: performance,
            encryption: encryption
        )

        let upload = FeatureUpload(
            featureName: configuration.name,
            contextProvider: contextProvider,
            fileReader: storage.reader,
            requestBuilder: configuration.requestBuilder,
            httpClient: httpClient,
            performance: performance
        )

        return Feature(
            storage: storage,
            upload: upload,
            configuration: featureSpecificConfiguration,
            messageReceiver: configuration.messageReceiver
        )
    }
}

/// A v1 Feature with an associated stroage.
internal protocol V1Feature {
    /// The feature's storage.
    var storage: FeatureStorage { get }

    /// The message receiver.
    ///
    /// The `FeatureMessageReceiver` defines an interface for Feature to receive any message
    /// from a bus that is shared between Features registered in a core.
    var messageReceiver: FeatureMessageReceiver { get }
}

/// This Scope complies with `V1FeatureScope` to provide context and writer to
/// v1 Features.
///
/// The execution block is currently running in `sync`, this will change once the
/// context is provided on it's own queue.
internal struct DatadogCoreFeatureScope: FeatureV1Scope {
    let context: DatadogV1Context
    let storage: FeatureStorage

    func eventWriteContext(bypassConsent: Bool, _ block: (DatadogV1Context, Writer) throws -> Void) {
        do {
            let writer = bypassConsent ? storage.arbitraryAuthorizedWriter : storage.writer
            try block(context, writer)
        } catch {
            DD.telemetry.error("Failed to execute feature scope", error: error)
        }
    }
}

extension DatadogV1Context {
    /// Create V1 context with the given congiguration and provider.
    ///
    /// - Parameters:
    ///   - configuration: The configuration.
    ///   - device: The device description.
    ///   - dateProvider: The local date provider.
    ///   - dateCorrector: The server date corrector.
    ///   - networkConnectionInfoProvider: The network info provider.
    ///   - carrierInfoProvider: The carrier info provider.
    ///   - userInfoProvider: The user info provider.
    ///   - appStateListener: The application state listener.
    ///   - launchTimeProvider: The launch time provider.
    init(
        configuration: CoreConfiguration,
        device: DeviceInfo,
        dateProvider: DateProvider,
        dateCorrector: DateCorrector,
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
        carrierInfoProvider: CarrierInfoProviderType,
        userInfoProvider: UserInfoProvider,
        appStateListener: AppStateListening,
        launchTimeProvider: LaunchTimeProviderType,
        featureAttributesProvider: FeatureAttributesProvider
    ) {
        self.site = configuration.site
        self.clientToken = configuration.clientToken
        self.service = configuration.serviceName
        self.env = configuration.environment
        self.version = configuration.applicationVersion
        self.source = configuration.source
        self.sdkVersion = configuration.sdkVersion
        self.ciAppOrigin = configuration.origin
        self.applicationName = configuration.applicationName
        self.applicationBundleIdentifier = configuration.applicationBundleIdentifier

        self.sdkInitDate = dateProvider.now
        self.device = device
        self.dateProvider = dateProvider
        self.dateCorrector = dateCorrector
        self.networkConnectionInfoProvider = networkConnectionInfoProvider
        self.carrierInfoProvider = carrierInfoProvider
        self.userInfoProvider = userInfoProvider
        self.appStateListener = appStateListener
        self.launchTimeProvider = launchTimeProvider
        self.featuresAttributesProvider = featureAttributesProvider
    }
}

extension DatadogContextProvider {
    /// Creates a core context provider with the given configuration,
    ///
    /// - Parameters:
    ///   - configuration: The configuration.
    ///   - device: The device description.
    ///   - dateProvider: The local date provider.
    convenience init(
        configuration: CoreConfiguration,
        device: DeviceInfo,
        dateProvider: DateProvider,
        serverDateProvider: ServerDateProvider
    ) {
        let context = DatadogContext(
            site: configuration.site,
            clientToken: configuration.clientToken,
            service: configuration.serviceName,
            env: configuration.environment,
            version: configuration.applicationVersion,
            source: configuration.source,
            sdkVersion: configuration.sdkVersion,
            ciAppOrigin: configuration.origin,
            applicationName: configuration.applicationName,
            applicationBundleIdentifier: configuration.applicationBundleIdentifier,
            sdkInitDate: dateProvider.now,
            device: device,
            // this is a placeholder waiting for the `ApplicationStatePublisher`
            // to be initialized on the main thread, this value will be overrided
            // as soon as the subscription is made.
            applicationStateHistory: .active(since: dateProvider.now)
        )

        self.init(context: context)

        subscribe(\.serverTimeOffset, to: ServerOffsetPublisher(provider: serverDateProvider))
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
            let applicationStatePublisher = ApplicationStatePublisher(dateProvider: dateProvider)
            self.subscribe(\.applicationStateHistory, to: applicationStatePublisher)
        }
        #endif
    }
}

/// A shim interface for allowing V1 Features generic initialization in `DatadogCore`.
internal protocol V1FeatureInitializable {
    /// The configuration specific to this Feature.
    /// In V2 this will likely become a part of the public interface for the Feature module.
    associatedtype Configuration

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: Configuration,
        messageReceiver: FeatureMessageReceiver
    )
}
