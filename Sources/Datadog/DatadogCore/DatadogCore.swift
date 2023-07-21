/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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
        autoreleaseFrequency: .workItem,
        target: .global(qos: .utility)
    )

    /// The message bus GDC queue.
    let messageBusQueue = DispatchQueue(
        label: "com.datadoghq.ios-sdk-message-bus",
        target: .global(qos: .utility)
    )

    /// The system date provider.
    let dateProvider: DateProvider

    /// The user consent publisher.
    let consentPublisher: TrackingConsentPublisher

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

    /// The application version publisher.
    let applicationVersionPublisher: ApplicationVersionPublisher

    /// The message bus used to dispatch messages to registered features.
    private var messageBus: [String: FeatureMessageReceiver] = [:]

    /// Registry for Features.
    @ReadWriteLock
    private(set) var v2Features: [String: (
        feature: DatadogFeature,
        storage: FeatureStorage,
        upload: FeatureUpload
    )] = [:]

    /// Registry for Feature Integrations.
    private var integrations: [String: DatadogFeatureIntegration] = [:]

    /// Registry for v1 features.
    private var v1Features: [String: Any] = [:]

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
    ///   - contextProvider: The core context provider.
    ///   - applicationVersion: The application version.
    init(
        directory: CoreDirectory,
        dateProvider: DateProvider,
        initialConsent: TrackingConsent,
        userInfoProvider: UserInfoProvider,
    	performance: PerformancePreset,
    	httpClient: HTTPClient,
    	encryption: DataEncryption?,
        contextProvider: DatadogContextProvider,
        applicationVersion: String
    ) {
        self.directory = directory
        self.dateProvider = dateProvider
        self.userInfoProvider = userInfoProvider
        self.performance = performance
        self.httpClient = httpClient
        self.encryption = encryption
        self.contextProvider = contextProvider
        self.applicationVersionPublisher = ApplicationVersionPublisher(version: applicationVersion)
        self.consentPublisher = TrackingConsentPublisher(consent: initialConsent)

        self.contextProvider.subscribe(\.userInfo, to: userInfoPublisher)
        self.contextProvider.subscribe(\.version, to: applicationVersionPublisher)
        self.contextProvider.subscribe(\.trackingConsent, to: consentPublisher)

        // forward any context change on the message-bus
        self.contextProvider.publish { [weak self] context in
            self?.send(message: .context(context))
        }
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

    /// Add or override the extra info of the current user
    ///
    ///  - Parameters:
    ///    - extraInfo: The user's custom attibutes to add or override
    func addUserExtraInfo(_ newExtraInfo: [AttributeKey: AttributeValue?]) {
        var extraInfo = userInfoPublisher.current.extraInfo
        newExtraInfo.forEach { extraInfo[$0.key] = $0.value }
        userInfoPublisher.current.extraInfo = extraInfo
        userInfoProvider.value.extraInfo = extraInfo
    }

    /// Sets the tracking consent regarding the data collection for the Datadog SDK.
    /// 
    /// - Parameter trackingConsent: new consent value, which will be applied for all data collected from now on
    func set(trackingConsent: TrackingConsent) {
        if trackingConsent != consentPublisher.consent {
            allStorages.forEach { $0.migrateUnauthorizedData(toConsent: trackingConsent) }
            consentPublisher.consent = trackingConsent
        }
    }

    /// Clears all data that has not already yet been uploaded Datadog servers.
    func clearAllData() {
        allStorages.forEach { $0.clearAllData() }
    }

    /// Adds a message receiver to the bus.
    ///
    /// After being added to the bus, the core will send the current context to receiver.
    ///
    /// - Parameters:
    ///   - messageReceiver: The new message receiver.
    ///   - key: The key associated with the receiver.
    private func add(messageReceiver: FeatureMessageReceiver, forKey key: String) {
        messageBusQueue.async { self.messageBus[key] = messageReceiver }
        contextProvider.read { context in
            self.messageBusQueue.async { messageReceiver.receive(message: .context(context), from: self) }
        }
    }

    /// A list of storage units of currently registered Features.
    private var allStorages: [FeatureStorage] {
        let v1Storages = v1Features.values.compactMap { $0 as? V1Feature }.map { $0.storage }
        let v2Storages = v2Features.values.map { $0.storage }
        return v1Storages + v2Storages
    }

    /// A list of upload units of currently registered Features.
    private var allUploads: [FeatureUpload] {
        let v1Uploads = [
            feature(LoggingFeature.self)?.upload,
            feature(TracingFeature.self)?.upload,
            feature(RUMFeature.self)?.upload,
        ].compactMap { $0 }
        let v2Uploads = v2Features.values.map { $0.upload }
        return v1Uploads + v2Uploads
    }

    /// Flushes asynchronous operations related to events write, context and message bus propagation in this instance of the SDK
    /// with **blocking the caller thread** till their completion.
    ///
    /// Upon return, it is safe to assume that all events are stored. No assumption on their upload should be made - to force events upload
    /// use `flushAndTearDown()` instead.
    func flush() {
        // The order of flushing below must be considered cautiously and
        // follow our design choices around SDK core's threading.

        // The flushing is repeated few times, to make sure that operations spawned from other operations
        // on these queues are also awaited. Effectively, this is no different than short-time sleep() on current
        // thread and it has the same drawbacks (including: it might become flaky). Until we find a better solution
        // this is enough to get consistency in tests - but won't be reliable in any public "deinitialize" API.
        for _ in 0..<5 {
            // First, flush bus queue - because messages can lead to obtaining "event write context" (reading
            // context & performing write) in other Features:
            messageBusQueue.sync { }

            // Next, flush context queue - because it indicates the entry point to "event write context" and
            // actual writes dispatched from it:
            contextProvider.queue.sync { }

            // Last, flush read-write queue - it always comes last, no matter if the write operation is dispatched
            // from "event write context" started on user thread OR if it happens upon receiving an "event" message
            // in other Feature:
            readWriteQueue.sync { }
        }
    }

    /// Awaits completion of all asynchronous operations, forces uploads (without retrying) and deinitializes
    /// this instance of the SDK. It **blocks the caller thread**.
    ///
    /// Upon return, it is safe to assume that all events were stored and got uploaded. The SDK was deinitialised so this instance of core is missfunctional.
    func flushAndTearDown() {
        flush()

        // At this point we can assume that all write operations completed and resulted with writing events to
        // storage. We now temporarily authorize storage for making all files readable ("uploadable") and perform
        // arbitrary uploads (without retrying on failure).
        allStorages.forEach { $0.setIgnoreFilesAgeWhenReading(to: true) }
        allUploads.forEach { $0.flushAndTearDown() }
        allStorages.forEach { $0.setIgnoreFilesAgeWhenReading(to: false) }

        // Deinitialize arbitrary V1 Features:
        feature(RUMInstrumentation.self)?.deinitialize()
        feature(URLSessionAutoInstrumentation.self)?.deinitialize()

        // Deinitialize V2 Integrations (arbitrarily for now, until we make it into `DatadogFeatureIntegration`):
        integration(named: "crash-reporter", type: CrashReporter.self)?.deinitialize()

        // Deallocate all Features and their storage & upload units:
        v1Features = [:]
        v2Features = [:]
        integrations = [:]
    }
}

extension DatadogCore: DatadogCoreProtocol {
    /// Registers a Feature instance.
    ///
    /// A Feature collects and transfers data to a Datadog Product (e.g. Logs, RUM, ...). A registered Feature can
    /// open a `FeatureScope` to write events, the core will then be responsible for storing and uploading events
    /// in a efficient manner. Performance presets for storage and upload are define when instanciating the core instance.
    ///
    /// A Feature can also communicate to other Features by sending message on the bus that is managed by the core.
    ///
    /// - Parameter feature: The Feature instance.
    /* public */ func register(feature: DatadogFeature) throws {
        let featureDirectories = try directory.getFeatureDirectories(forFeatureNamed: feature.name)

        let performancePreset: PerformancePreset
        if let override = feature.performanceOverride {
            performancePreset = performance.updated(with: override)
        } else {
            performancePreset = performance
        }

        let storage = FeatureStorage(
            featureName: feature.name,
            queue: readWriteQueue,
            directories: featureDirectories,
            dateProvider: dateProvider,
            performance: performancePreset,
            encryption: encryption
        )

        let upload = FeatureUpload(
            featureName: feature.name,
            contextProvider: contextProvider,
            fileReader: storage.reader,
            requestBuilder: feature.requestBuilder,
            httpClient: httpClient,
            performance: performancePreset
        )

        v2Features[feature.name] = (
            feature: feature,
            storage: storage,
            upload: upload
        )

        // If there is any persisted data recorded with `.pending` consent,
        // it should be deleted on Feature startup:
        storage.clearUnauthorizedData()

        add(messageReceiver: feature.messageReceiver, forKey: feature.name)
    }

    /// Retrieves a Feature by its name and type.
    ///
    /// A Feature type can be specified as parameter or inferred from the return type:
    ///
    ///     let feature = core.feature(named: "foo", type: Foo.self)
    ///     let feature: Foo? = core.feature(named: "foo")
    ///
    /// - Parameters:
    ///   - name: The Feature's name.
    ///   - type: The Feature instance type.
    /// - Returns: The Feature if any.
    /* public */ func feature<T>(named name: String, type: T.Type = T.self) -> T? where T: DatadogFeature {
        v2Features[name]?.feature as? T
    }

    /// Registers a Feature Integration instance.
    ///
    /// A Feature Integration collect and transfer data to a local Datadog Feature. An Integration will not store nor upload,
    /// it will collect data for other Features to consume.
    ///
    /// An Integration can commicate to Features via dependency or a communication channel such as the message-bus.
    ///
    /// - Parameter integration: The Feature Integration instance.
    /* public */ func register(integration: DatadogFeatureIntegration) throws {
        integrations[integration.name] = integration
        add(messageReceiver: integration.messageReceiver, forKey: integration.name)
    }

    /// Retrieves a Feature Integration by its name and type.
    ///
    /// A Feature Integration type can be specified as parameter or inferred from the return type:
    ///
    ///     let integration = core.integration(named: "foo", type: Foo.self)
    ///     let integration: Foo? = core.integration(named: "foo")
    ///
    /// - Parameters:
    ///   - name: The Feature Integration's name.
    ///   - type: The Feature Integration instance type.
    /// - Returns: The Feature Integration if any.
    /* public */ func integration<T>(named name: String, type: T.Type = T.self) -> T? where T: DatadogFeatureIntegration {
        integrations[name] as? T
    }

    /* public */ func scope(for feature: String) -> FeatureScope? {
        guard let storage = v2Features[feature]?.storage else {
            return nil
        }

        return DatadogCoreFeatureScope(
            contextProvider: contextProvider,
            storage: storage
        )
    }

    /* public */ func set(feature: String, attributes: @escaping () -> FeatureBaggage) {
        contextProvider.write { $0.featuresAttributes[feature] = attributes() }
    }

    /* public */ func update(feature: String, attributes: @escaping () -> FeatureBaggage) {
        contextProvider.write {
            if $0.featuresAttributes[feature] != nil {
                $0.featuresAttributes[feature]?.merge(with: attributes())
            } else {
                $0.featuresAttributes[feature] = attributes()
            }
        }
    }

    /* public */ func send(message: FeatureMessage, sender: DatadogCoreProtocol, else fallback: @escaping () -> Void) {
        messageBusQueue.async {
            let receivers = self.messageBus.values.filter {
                $0.receive(message: message, from: sender)
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

        if let feature = instance as? V1Feature {
            add(messageReceiver: feature.messageReceiver, forKey: key)
        }
    }

    func feature<T>(_ type: T.Type) -> T? {
        let key = String(describing: T.self)
        return v1Features[key] as? T
    }

    func scope<T>(for featureType: T.Type) -> FeatureScope? {
        let key = String(describing: T.self)

        guard let feature = v1Features[key] as? V1Feature else {
            return nil
        }

        return DatadogCoreFeatureScope(
            contextProvider: contextProvider,
            storage: feature.storage
        )
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

        // If there is any persisted data recorded with `.pending` consent,
        // it should be deleted on Feature startup:
        storage.clearUnauthorizedData()

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

internal struct DatadogCoreFeatureScope: FeatureScope {
    let contextProvider: DatadogContextProvider
    let storage: FeatureStorage

    func eventWriteContext(bypassConsent: Bool, forceNewBatch: Bool, _ block: @escaping (DatadogContext, Writer) throws -> Void) {
        // On user thread: request SDK context.
        contextProvider.read { context in
            // On context thread: request writer for current tracking consent.
            let writer = storage.writer(
                for: bypassConsent ? .granted : context.trackingConsent,
                forceNewBatch: forceNewBatch
            )

            // Still on context thread: send `Writer` to EWC caller. The writer implements `AsyncWriter`, so
            // the implementation of `writer.write(value:)` will run asynchronously without blocking the context thread.
            do {
                try block(context, writer)
            } catch {
                DD.telemetry.error("Failed to execute feature scope", error: error)
            }
        }
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
        serverDateProvider: ServerDateProvider
    ) {
        let context = DatadogContext(
            site: configuration.site,
            clientToken: configuration.clientToken,
            service: configuration.serviceName,
            env: configuration.environment,
            version: configuration.applicationVersion,
            variant: configuration.variant,
            source: configuration.source,
            sdkVersion: configuration.sdkVersion,
            ciAppOrigin: configuration.origin,
            applicationName: configuration.applicationName,
            applicationBundleIdentifier: configuration.applicationBundleIdentifier,
            sdkInitDate: configuration.dateProvider.now,
            device: device,
            // this is a placeholder waiting for the `ApplicationStatePublisher`
            // to be initialized on the main thread, this value will be overrided
            // as soon as the subscription is made.
            applicationStateHistory: .active(since: configuration.dateProvider.now)
        )

        self.init(context: context)

        subscribe(\.serverTimeOffset, to: ServerOffsetPublisher(provider: serverDateProvider))
        subscribe(\.launchTime, to: LaunchTimePublisher())

        if #available(iOS 12, tvOS 12, *) {
            subscribe(\.networkConnectionInfo, to: NWPathMonitorPublisher())
        } else {
            assign(reader: SCNetworkReachabilityReader(), to: \.networkConnectionInfo)
        }

        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 12, *) {
            subscribe(\.carrierInfo, to: iOS12CarrierInfoPublisher())
        } else {
            assign(reader: iOS11CarrierInfoReader(), to: \.carrierInfo)
        }
        #endif

        #if os(iOS) && !targetEnvironment(simulator)
        subscribe(\.batteryStatus, to: BatteryStatusPublisher())
        subscribe(\.isLowPowerModeEnabled, to: LowPowerModePublisher())
        #endif

        #if os(iOS) || os(tvOS)
        DispatchQueue.main.async {
            // must be call on the main thread to read `UIApplication.State`
            let applicationStatePublisher = ApplicationStatePublisher(dateProvider: configuration.dateProvider)
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
