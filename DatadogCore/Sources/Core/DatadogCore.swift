/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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

    /// The system date provider.
    let dateProvider: DateProvider

    /// The user consent publisher.
    let consentPublisher: TrackingConsentPublisher

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

    /// The message-bus instance.
    let bus = MessageBus()

    /// Registry for Features.
    @ReadWriteLock
    private(set) var stores: [String: (
        storage: FeatureStorage,
        upload: FeatureUpload
    )] = [:]

    /// Registry for Features.
    @ReadWriteLock
    private var features: [String: DatadogFeature] = [:]

    /// The core context provider.
    internal let contextProvider: DatadogContextProvider

    /// Flag defining if background tasks are enabled.
    internal let backgroundTasksEnabled: Bool

    /// Maximum number of batches per upload.
    internal let maxBatchesPerUpload: Int

    /// Creates a core instance.
    ///
    /// - Parameters:
    ///   - directory: The core directory for this instance of the SDK.
    ///   - dateProvider: The system date provider.
    ///   - initialConsent: The initial user consent.
    ///   - performance: The core SDK performance presets.
    ///   - httpClient: The HTTP Client for uploads.
    ///   - encryption: The on-disk data encryption.
    ///   - contextProvider: The core context provider.
    ///   - applicationVersion: The application version.
    init(
        directory: CoreDirectory,
        dateProvider: DateProvider,
        initialConsent: TrackingConsent,
    	performance: PerformancePreset,
    	httpClient: HTTPClient,
    	encryption: DataEncryption?,
        contextProvider: DatadogContextProvider,
        applicationVersion: String,
        maxBatchesPerUpload: Int,
        backgroundTasksEnabled: Bool
    ) {
        self.directory = directory
        self.dateProvider = dateProvider
        self.performance = performance
        self.httpClient = httpClient
        self.encryption = encryption
        self.contextProvider = contextProvider
        self.maxBatchesPerUpload = maxBatchesPerUpload
        self.backgroundTasksEnabled = backgroundTasksEnabled
        self.applicationVersionPublisher = ApplicationVersionPublisher(version: applicationVersion)
        self.consentPublisher = TrackingConsentPublisher(consent: initialConsent)

        self.contextProvider.subscribe(\.userInfo, to: userInfoPublisher)
        self.contextProvider.subscribe(\.version, to: applicationVersionPublisher)
        self.contextProvider.subscribe(\.trackingConsent, to: consentPublisher)

        // connect the core to the message bus.
        // the bus will keep a weak ref to the core.
        bus.connect(core: self)

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
    }

    /// Add or override the extra info of the current user
    ///
    ///  - Parameters:
    ///    - extraInfo: The user's custom attibutes to add or override
    func addUserExtraInfo(_ newExtraInfo: [AttributeKey: AttributeValue?]) {
        var extraInfo = userInfoPublisher.current.extraInfo
        newExtraInfo.forEach { extraInfo[$0.key] = $0.value }
        userInfoPublisher.current.extraInfo = extraInfo
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
        bus.connect(messageReceiver, forKey: key)
        contextProvider.read { context in
            self.bus.queue.async { messageReceiver.receive(message: .context(context), from: self) }
        }
    }

    /// A list of storage units of currently registered Features.
    private var allStorages: [FeatureStorage] {
        stores.values.map { $0.storage }
    }

    /// A list of upload units of currently registered Features.
    private var allUploads: [FeatureUpload] {
        stores.values.map { $0.upload }
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

        stop()
    }

    /// Stops all processes for this instance of the Datadog core by
    /// deallocating all Features and their storage & upload units.
    func stop() {
        stores = [:]
        features = [:]
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
    func register<T>(feature: T) throws where T: DatadogFeature {
        if let feature = feature as? DatadogRemoteFeature {
            let featureDirectories = try directory.getFeatureDirectories(forFeatureNamed: T.name)

            let performancePreset: PerformancePreset
            if let override = feature.performanceOverride {
                performancePreset = performance.updated(with: override)
            } else {
                performancePreset = performance
            }

            let storage = FeatureStorage(
                featureName: T.name,
                queue: readWriteQueue,
                directories: featureDirectories,
                dateProvider: dateProvider,
                performance: performancePreset,
                encryption: encryption,
                telemetry: telemetry
            )

            let upload = FeatureUpload(
                featureName: T.name,
                contextProvider: contextProvider,
                fileReader: storage.reader,
                requestBuilder: feature.requestBuilder,
                httpClient: httpClient,
                performance: performancePreset,
                backgroundTasksEnabled: backgroundTasksEnabled,
                maxBatchesPerUpload: maxBatchesPerUpload,
                telemetry: telemetry
            )

            stores[T.name] = (
                storage: storage,
                upload: upload
            )

            // If there is any persisted data recorded with `.pending` consent,
            // it should be deleted on Feature startup:
            storage.clearUnauthorizedData()
        }

        features[T.name] = feature
        add(messageReceiver: feature.messageReceiver, forKey: T.name)
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
    func get<T>(feature type: T.Type = T.self) -> T? where T: DatadogFeature {
        features[T.name] as? T
    }

    func scope<Feature>(for featureType: Feature.Type) -> FeatureScope where Feature: DatadogFeature {
        return CoreFeatureScope<Feature>(in: self)
    }

    func set(baggage: @escaping () -> FeatureBaggage?, forKey key: String) {
        contextProvider.write { $0.baggages[key] = baggage() }
    }

    func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        bus.send(message: message, else: fallback)
    }
}

internal class CoreFeatureScope<Feature>: FeatureScope where Feature: DatadogFeature {
    private weak var core: DatadogCore?
    private let store: FeatureDataStore

    init(in core: DatadogCore) {
        self.core = core
        self.store = FeatureDataStore(
            feature: Feature.name,
            directory: core.directory,
            queue: core.readWriteQueue,
            telemetry: core.telemetry
        )
    }

    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        // Capture the core reference so it is available until async block completion. This is ensure
        // that we write events which were collected right before deallocating the core on the current thread.
        guard let core = core else {
            return // core is deinitialized
        }

        // (on user thread) request SDK context
        context { context in
            // (on context thread)
            guard let storage = core.stores[Feature.name]?.storage else {
                if core.get(feature: Feature.self) == nil { // the core was stopped
                    DD.logger.warn(
                        "Failed to obtain Event Write Context for '\(Feature.name)' because this feature is no longer running."
                    )
                } else { // core is running, but this is wrong Feature type
                    DD.logger.error(
                        "Failed to obtain Event Write Context for '\(Feature.name)' because it is not a `DatadogRemoteFeature`."
                    )
                    #if DEBUG
                    assertionFailure("Obtaining Event Write Context for '\(Feature.name)' but it is not a `DatadogRemoteFeature`.")
                    #endif
                }
                return
            }
            let writer = storage.writer(for: bypassConsent ? .granted : context.trackingConsent)
            block(context, writer)
        }
    }

    func context(_ block: @escaping (DatadogContext) -> Void) {
        // (on user thread) request SDK context
        core?.contextProvider.read { context in
            // (on context thread) call the block
            block(context)
        }
    }

    var dataStore: DataStore {
        // Data store is only available when core instance exists.
        return (core != nil) ? store : NOPDataStore()
    }
}

extension DatadogContextProvider {
    /// Creates a core context provider with the given configuration,
    convenience init(
        site: DatadogSite,
        clientToken: String,
        service: String,
        env: String,
        version: String,
        buildNumber: String,
        buildId: String?,
        variant: String?,
        source: String,
        nativeSourceOverride: String?,
        sdkVersion: String,
        ciAppOrigin: String?,
        applicationName: String,
        applicationBundleIdentifier: String,
        applicationVersion: String,
        sdkInitDate: Date,
        device: DeviceInfo,
        dateProvider: DateProvider,
        serverDateProvider: ServerDateProvider
    ) {
        let context = DatadogContext(
            site: site,
            clientToken: clientToken,
            service: service,
            env: env,
            version: applicationVersion,
            buildNumber: buildNumber,
            buildId: buildId,
            variant: variant,
            source: source,
            sdkVersion: sdkVersion,
            ciAppOrigin: ciAppOrigin,
            applicationName: applicationName,
            applicationBundleIdentifier: applicationBundleIdentifier,
            sdkInitDate: dateProvider.now,
            device: device,
            nativeSourceOverride: nativeSourceOverride,
            // this is a placeholder waiting for the `ApplicationStatePublisher`
            // to be initialized on the main thread, this value will be overrided
            // as soon as the subscription is made.
            applicationStateHistory: .active(since: dateProvider.now)
        )

        self.init(context: context)

        subscribe(\.serverTimeOffset, to: ServerOffsetPublisher(provider: serverDateProvider))
        subscribe(\.launchTime, to: LaunchTimePublisher())

        if #available(iOS 12, tvOS 12, *) {
            subscribe(\.networkConnectionInfo, to: NWPathMonitorPublisher())
        } else {
            assign(reader: SCNetworkReachabilityReader(), to: \.networkConnectionInfo)
        }
        #if os(iOS) && !targetEnvironment(macCatalyst) && !(swift(>=5.9) && os(visionOS))
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
            let applicationStatePublisher = ApplicationStatePublisher(dateProvider: dateProvider)
            self.subscribe(\.applicationStateHistory, to: applicationStatePublisher)
        }
        #endif
    }
}

extension DatadogCore: Flushable {
    /// Flushes asynchronous operations related to events write, context and message bus propagation in this instance of the SDK
    /// with **blocking the caller thread** till their completion.
    ///
    /// Upon return, it is safe to assume that all events are stored. No assumption on their upload should be made - to force events upload
    /// use `flushAndTearDown()` instead.
    func flush() {
        // The order of flushing below must be considered cautiously and
        // follow our design choices around SDK core's threading.

        let features = features.values.compactMap { $0 as? Flushable }

        // The flushing is repeated few times, to make sure that operations spawned from other operations
        // on these queues are also awaited. Effectively, this is no different than short-time sleep() on current
        // thread and it has the same drawbacks (including: it might become flaky). Until we find a better solution
        // this is enough to get consistency in tests - but won't be reliable in any public "deinitialize" API.
        for _ in 0..<5 {
            // First, flush bus queue - because messages can lead to obtaining "event write context" (reading
            // context & performing write) in other Features:
            bus.flush()

            // Next, flush flushable Features - finish current data collection to open "event write contexts":
            features.forEach { $0.flush() }

            // Next, flush context queue - because it indicates the entry point to "event write context" and
            // actual writes dispatched from it:
            contextProvider.flush()

            // Last, flush read-write queue - it always comes last, no matter if the write operation is dispatched
            // from "event write context" started on user thread OR if it happens upon receiving an "event" message
            // in other Feature:
            readWriteQueue.sync { }
        }
    }
}
