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

    /// The account info publisher that publishes value to the
    /// `contextProvider`
    let accountInfoPublisher = AccountInfoPublisher()

    /// The application version publisher.
    let applicationVersionPublisher: ApplicationVersionPublisher

    /// The message-bus instance.
    let bus = MessageBus()

    /// Registry for Features.
    @ReadWriteLock
    private(set) var stores: [String: (storage: FeatureStorage, upload: FeatureUpload)] = [:]

    /// Registry for Features.
    @ReadWriteLock
    private var features: [String: DatadogFeature] = [:]

    /// The core context provider.
    internal let contextProvider: DatadogContextProvider

    /// Flag defining if background tasks are enabled.
    internal let backgroundTasksEnabled: Bool

    /// Flag defining if the SDK is run from an extension.
    internal let isRunFromExtension: Bool

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
        backgroundTasksEnabled: Bool,
        isRunFromExtension: Bool = false
    ) {
        self.directory = directory
        self.dateProvider = dateProvider
        self.performance = performance
        self.httpClient = httpClient
        self.encryption = encryption
        self.contextProvider = contextProvider
        self.maxBatchesPerUpload = maxBatchesPerUpload
        self.backgroundTasksEnabled = backgroundTasksEnabled
        self.isRunFromExtension = isRunFromExtension
        self.applicationVersionPublisher = ApplicationVersionPublisher(version: applicationVersion)
        self.consentPublisher = TrackingConsentPublisher(consent: initialConsent)
        self.contextProvider.subscribe(\.userInfo, to: userInfoPublisher)
        self.contextProvider.subscribe(\.accountInfo, to: accountInfoPublisher)
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
            anonymousId: userInfoPublisher.current.anonymousId,
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

    /// Clear the current user information
    ///
    /// User information will be `nil`
    /// Following Logs, Traces, RUM Events will not include the user information anymore
    ///
    /// Any active RUM Session, active RUM View at the time of call will have their `user` attribute emptied
    ///
    /// If you want to retain the current `user` on the active RUM session,
    /// you need to stop the session first by using `RUMMonitor.stopSession()`
    ///
    /// If you want to retain the current `user` on the active RUM views,
    /// you need to stop the view first by using `RUMMonitor.stopView(viewController:attributes:)`
    ///
    func clearUserInfo() {
        userInfoPublisher.current = UserInfo(anonymousId: userInfoPublisher.current.anonymousId)
    }

    /// Sets current account information.
    ///
    /// Those will be added to logs, traces and RUM events automatically.
    ///
    /// - Parameters:
    ///   - id: Account ID
    ///   - name: Name representing the account, if any
    ///   - extraInfo: Account's custom attributes, if any
    func setAccountInfo(
        id: String,
        name: String? = nil,
        extraInfo: [AttributeKey: AttributeValue] = [:]
    ) {
        let accountInfo = AccountInfo(
            id: id,
            name: name,
            extraInfo: extraInfo
        )
        accountInfoPublisher.current = accountInfo
    }

    /// Add or override the extra info of the current account
    ///
    ///  - Parameters:
    ///    - extraInfo: The account's custom attibutes to add or override
    func addAccountExtraInfo(_ newExtraInfo: [AttributeKey: AttributeValue?]) {
        guard let accountInfo = accountInfoPublisher.current else {
            DD.logger.error(
                "Failed to add Account ExtraInfo because no Account Info exist yet. Please call `setAccountInfo` first."
            )
            #if DEBUG
            assertionFailure("Failed to add Account ExtraInfo because no Account Info exist yet. Please call `setAccountInfo` first.")
            #endif
            return
        }
        var extraInfo = accountInfo.extraInfo
        newExtraInfo.forEach { extraInfo[$0.key] = $0.value }
        accountInfoPublisher.current?.extraInfo = extraInfo
    }

    /// Clear the current account information
    ///
    /// Account information will be `nil`
    /// Following Logs, Traces, RUM Events will not include the account information anymore
    ///
    /// Any active RUM Session, active RUM View at the time of call will have their `account` attribute emptied
    ///
    /// If you want to retain the current `account` on the active RUM session,
    /// you need to stop the session first by using `RUMMonitor.stopSession()`
    ///
    /// If you want to retain the current `account` on the active RUM views,
    /// you need to stop the view first by using `RUMMonitor.stopView(viewController:attributes:)`
    ///
    func clearAccountInfo() {
        accountInfoPublisher.current = nil
    }

    /// Sets the tracking consent regarding the data collection for the Datadog SDK.
    ///
    /// - Parameter trackingConsent: new consent value, which will be applied for all data collected from now on
    func set(trackingConsent: TrackingConsent) {
        if trackingConsent != consentPublisher.consent {
            contextProvider.queue.async { [allStorages] in
                // RUM-3175: To prevent race conditions with ongoing "event write" operations,
                // data migration must be synchronized on the context queue. This guarantees that
                // all latest events have been written before migration occurs.
                allStorages.forEach { $0.migrateUnauthorizedData(toConsent: trackingConsent) }
            }
            consentPublisher.consent = trackingConsent
        }
    }

    /// Clears all data that has not already yet been uploaded Datadog servers.
    func clearAllData() {
        allStorages.forEach { $0.clearAllData() }
        allDataStores.forEach { $0.clearAllData() }
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

    private var allDataStores: [DataStore] {
        features.values.compactMap { feature in
            let featureType = type(of: feature) as DatadogFeature.Type
            return scope(for: featureType).dataStore
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
                backgroundTasksEnabled: backgroundTasksEnabled,
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
                isRunFromExtension: isRunFromExtension,
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
    func feature<T>(named name: String, type: T.Type) -> T? {
        features[name] as? T
    }

    func scope<Feature>(for featureType: Feature.Type) -> FeatureScope where Feature: DatadogFeature {
        return CoreFeatureScope<Feature>(in: self)
    }

    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {
        contextProvider.write { $0.set(additionalContext: context()) }
    }

    func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        bus.send(message: message, else: fallback)
    }

    func set(anonymousId: String?) {
        userInfoPublisher.current.anonymousId = anonymousId
    }
}

internal class CoreFeatureScope<Feature>: @unchecked Sendable, FeatureScope where Feature: DatadogFeature {
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
        guard let core = core else {
            return  // core is deinitialized
        }
        // Capture the storage reference so it is available until async block completion. This is to ensure
        // that we write events which were collected on the caller thread even if the core was released in the meantime.
        guard let storage = core.stores[Feature.name]?.storage else {
            if core.get(feature: Feature.self) != nil { // the feature is running, but has no storage
                DD.logger.error(
                    "Failed to obtain Event Write Context for '\(Feature.name)' because it is not a `DatadogRemoteFeature`."
                )
                #if DEBUG
                assertionFailure("Obtaining Event Write Context for '\(Feature.name)' but it is not a `DatadogRemoteFeature`.")
                #endif
            }
            return
        }

        // (on user thread) request SDK context
        context { context in
            // (on context thread) call the block
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
        return (core != nil) ? store : NOPDataStore() // only available when the core exists
    }

    func send(message: FeatureMessage, else fallback: @escaping () -> Void) {
        core?.send(message: message, else: fallback)
    }

    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {
        core?.set(context: context)
    }

    func set(anonymousId: String?) {
        core?.set(anonymousId: anonymousId)
    }

    var telemetry: Telemetry {
        return core?.telemetry ?? NOPTelemetry()
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
        applicationBundleType: BundleType,
        applicationVersion: String,
        sdkInitDate: Date,
        device: DeviceInfo,
        os: OperatingSystem,
        locale: LocaleInfo,
        processInfo: ProcessInfo,
        dateProvider: DateProvider,
        serverDateProvider: ServerDateProvider,
        notificationCenter: NotificationCenter,
        appLaunchHandler: AppLaunchHandling,
        appStateProvider: AppStateProvider
    ) {
        // `ContextProvider` must be initialized on the main thread for two key reasons:
        // - It interacts with UIKit APIs to read the initial app state, which is only safe on the main thread.
        // - It subscribes to app state change notifications, and we need this subscription to occur
        //   before any Feature subscriptions. This ensures that Core always processes state changes first.
        dd_assert(Thread.isMainThread, "Must be called on main thread")

        let initialAppState = appStateProvider.current
        let appStateHistory = AppStateHistory(initialState: initialAppState, date: dateProvider.now)
        let launchInfo = appLaunchHandler.resolveLaunchInfo(using: processInfo)

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
            applicationBundleType: applicationBundleType,
            sdkInitDate: dateProvider.now,
            device: device,
            os: os,
            localeInfo: locale,
            nativeSourceOverride: nativeSourceOverride,
            launchInfo: launchInfo,
            applicationStateHistory: appStateHistory
        )

        self.init(context: context)

        subscribe(\.serverTimeOffset, to: ServerOffsetPublisher(provider: serverDateProvider))

        #if !os(macOS)
        subscribe(\.launchInfo, to: LaunchInfoPublisher(handler: appLaunchHandler, initialValue: launchInfo))
        #endif

        subscribe(\.networkConnectionInfo, to: NWPathMonitorPublisher())

        #if os(iOS) && !targetEnvironment(macCatalyst) && !(swift(>=5.9) && os(visionOS))
        subscribe(\.carrierInfo, to: CarrierInfoPublisher())
        #endif

        #if os(iOS) && !targetEnvironment(simulator)
        subscribe(\.batteryStatus, to: BatteryStatusPublisher(notificationCenter: notificationCenter, device: .current))
        subscribe(\.isLowPowerModeEnabled, to: LowPowerModePublisher(notificationCenter: notificationCenter, processInfo: processInfo))
        #endif

        #if os(iOS)
        subscribe(\.brightnessLevel, to: BrightnessLevelPublisher(notificationCenter: notificationCenter))
        #endif

        subscribe(\.localeInfo, to: LocaleInfoPublisher(initialLocale: locale, notificationCenter: notificationCenter))

        #if os(iOS) || os(tvOS)
        let applicationStatePublisher = ApplicationStatePublisher(
            appStateHistory: appStateHistory,
            notificationCenter: notificationCenter,
            dateProvider: dateProvider
        )
        self.subscribe(\.applicationStateHistory, to: applicationStatePublisher)
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

        // Reset baggages that need not be persisted across flushes.
        removeContext(ofType: LaunchReport.self)

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

extension DatadogCore: Storage {
    /// Returns the most recent modification date of a file in the core directory.
    /// - Parameter before: The date to compare the last modification date of files.
    /// - Returns: The latest modified file or `nil` if no files were modified before given date.
    func mostRecentModifiedFileAt(before: Date) throws -> Date? {
        try readWriteQueue.sync {
            let file = try directory.coreDirectory.mostRecentModifiedFile(before: before)
            return try file?.modifiedAt()
        }
    }
}
// swiftlint:disable duplicate_imports
#if SPM_BUILD
    #if swift(>=6.0)
    internal import DatadogPrivate
    #else
    @_implementationOnly import DatadogPrivate
    #endif
#endif
// swiftlint:enable duplicate_imports

internal let registerObjcExceptionHandlerOnce: () -> Void = {
    ObjcException.rethrow = __dd_private_ObjcExceptionHandler.rethrow
    return {}
}()
