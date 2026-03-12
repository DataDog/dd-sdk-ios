/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@preconcurrency import DatadogInternal

/// Core implementation of Datadog SDK.
///
/// The core provides a storage and upload mechanism for each registered Feature
/// based on their respective configuration.
///
/// By complying with `DatadogCoreProtocol`, the core can
/// provide context and writing scopes to Features for event recording.
internal final class DatadogCore: @unchecked Sendable {
    /// The root location for storing Features data in this instance of the SDK.
    /// For each Feature a set of subdirectories is created inside `CoreDirectory` based on their storage configuration.
    let directory: CoreDirectory

    /// The system date provider.
    let dateProvider: DateProvider

    /// The core SDK performance presets.
    let performance: PerformancePreset

    /// The HTTP Client for uploads.
    let httpClient: HTTPClient

    /// The on-disk data encryption.
    let encryption: DataEncryption?

    /// The message-bus instance.
    let bus = MessageBus()

    /// The actor managing feature registrations, storage, and upload.
    let featureStore = FeatureStore()

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

        Task {
            await contextProvider.write { context in
                context.userInfo = .empty
                context.trackingConsent = initialConsent
                context.version = applicationVersion
            }

            // connect the core to the message bus.
            await bus.connect(core: self)

            // forward any context change on the message-bus
            await contextProvider.publish { [weak self] context in
                self?.send(message: .context(context))
            }
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
        Task {
            await contextProvider.write { context in
                context.userInfo = UserInfo(
                    anonymousId: context.userInfo?.anonymousId,
                    id: id,
                    name: name,
                    email: email,
                    extraInfo: extraInfo
                )
            }
        }
    }

    /// Add or override the extra info of the current user
    ///
    ///  - Parameters:
    ///    - extraInfo: The user's custom attributes to add or override
    func addUserExtraInfo(_ newExtraInfo: [AttributeKey: AttributeValue?]) {
        Task {
            await contextProvider.write { context in
                var extraInfo = context.userInfo?.extraInfo ?? [:]
                newExtraInfo.forEach { extraInfo[$0.key] = $0.value }
                context.userInfo?.extraInfo = extraInfo
            }
        }
    }

    /// Clear the current user information
    func clearUserInfo() {
        Task {
            await contextProvider.write { context in
                context.userInfo = UserInfo(anonymousId: context.userInfo?.anonymousId)
            }
        }
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
        Task {
            await contextProvider.write { context in
                context.accountInfo = AccountInfo(
                    id: id,
                    name: name,
                    extraInfo: extraInfo
                )
            }
        }
    }

    /// Add or override the extra info of the current account
    ///
    ///  - Parameters:
    ///    - extraInfo: The account's custom attributes to add or override
    func addAccountExtraInfo(_ newExtraInfo: [AttributeKey: AttributeValue?]) {
        Task {
            await contextProvider.write { context in
                guard context.accountInfo != nil else {
                    DD.logger.error(
                        "Failed to add Account ExtraInfo because no Account Info exist yet. Please call `setAccountInfo` first."
                    )
                    #if DEBUG
                    assertionFailure("Failed to add Account ExtraInfo because no Account Info exist yet. Please call `setAccountInfo` first.")
                    #endif
                    return
                }
                var extraInfo = context.accountInfo?.extraInfo ?? [:]
                newExtraInfo.forEach { extraInfo[$0.key] = $0.value }
                context.accountInfo?.extraInfo = extraInfo
            }
        }
    }

    /// Clear the current account information
    func clearAccountInfo() {
        Task { await contextProvider.write { $0.accountInfo = nil } }
    }

    /// Sets the tracking consent regarding the data collection for the Datadog SDK.
    ///
    /// - Parameter trackingConsent: new consent value, which will be applied for all data collected from now on
    func set(trackingConsent: TrackingConsent) {
        let storages = featureStore.allStorages
        Task {
            await contextProvider.write { context in
                guard trackingConsent != context.trackingConsent else { return }
                context.trackingConsent = trackingConsent
            }
            for storage in storages {
                await storage.migrateUnauthorizedData(toConsent: trackingConsent)
            }
        }
    }

    /// Clears all data that has not already yet been uploaded Datadog servers.
    func clearAllData() {
        let storages = featureStore.allStorages
        let dataStores = featureStore.allDataStores(in: self)
        Task {
            for storage in storages {
                await storage.clearAllData()
            }
        }
        dataStores.forEach { $0.clearAllData() }
    }

    /// Adds a message receiver to the bus.
    ///
    /// After being added to the bus, the core will send the current context to the receiver.
    ///
    /// - Parameters:
    ///   - messageReceiver: The new message receiver.
    ///   - key: The key associated with the receiver.
    private func add(messageReceiver: FeatureMessageReceiver, forKey key: String) {
        nonisolated(unsafe) let receiver = messageReceiver
        Task { @Sendable in
            await bus.connect(receiver, forKey: key)
            let context = await contextProvider.read()
            await bus.sendInitialContext(context, forKey: key)
        }
    }

    /// Awaits completion of all asynchronous operations, forces uploads (without retrying) and deinitializes
    /// this instance of the SDK.
    ///
    /// Upon return, it is safe to assume that all events were stored and got uploaded. The SDK was deinitialised so this instance of core is non-functional.
    func flushAndTearDown() async {
        await flush()

        let storages = featureStore.allStorages
        let uploads = featureStore.allUploads

        for storage in storages {
            await storage.setIgnoreFilesAgeWhenReading(to: true)
        }

        uploads.forEach { $0.flushAndTearDown() }

        for storage in storages {
            await storage.setIgnoreFilesAgeWhenReading(to: false)
        }

        stop()
    }

    /// Stops all processes for this instance of the Datadog core by
    /// deallocating all Features and their storage & upload units.
    func stop() {
        featureStore.stop()
    }
}

extension DatadogCore: DatadogCoreProtocol {
    /// Registers a Feature instance.
    func register<T>(feature: T) throws where T: DatadogFeature {
        if let remoteFeature = feature as? DatadogRemoteFeature {
            let featureDirectories = try directory.getFeatureDirectories(forFeatureNamed: T.name)

            let performancePreset: PerformancePreset
            if let override = remoteFeature.performanceOverride {
                performancePreset = performance.updated(with: override)
            } else {
                performancePreset = performance
            }

            let storage = FeatureStorage(
                featureName: T.name,
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
                requestBuilder: remoteFeature.requestBuilder,
                httpClient: httpClient,
                performance: performancePreset,
                backgroundTasksEnabled: backgroundTasksEnabled,
                isRunFromExtension: isRunFromExtension,
                telemetry: telemetry
            )

            featureStore.addStore(name: T.name, storage: storage, upload: upload)

            Task { await storage.clearUnauthorizedData() }
        }

        featureStore.addFeature(name: T.name, feature: feature)
        add(messageReceiver: feature.messageReceiver, forKey: T.name)
    }

    /// Retrieves a Feature by its name and type.
    func feature<T>(named name: String, type: T.Type) -> T? {
        featureStore.feature(named: name, type: type)
    }

    func scope<Feature>(for featureType: Feature.Type) -> FeatureScope where Feature: DatadogFeature {
        return CoreFeatureScope<Feature>(in: self)
    }

    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {
        nonisolated(unsafe) let value = context()
        Task { @Sendable in await contextProvider.write { $0.set(additionalContext: value) } }
    }

    func send(message: FeatureMessage, else fallback: @escaping @Sendable () -> Void) {
        Task { await bus.send(message: message, else: fallback) }
    }

    func set(anonymousId: String?) {
        Task { await contextProvider.write { $0.userInfo?.anonymousId = anonymousId } }
    }

    /// Sets the application version on the context.
    func set(version: String) {
        Task { await contextProvider.write { $0.version = version } }
    }
}

internal final class CoreFeatureScope<Feature>: @unchecked Sendable, FeatureScope where Feature: DatadogFeature {
    private weak var core: DatadogCore?
    private let store: FeatureDataStore

    init(in core: DatadogCore) {
        self.core = core
        self.store = FeatureDataStore(
            feature: Feature.name,
            directory: core.directory,
            telemetry: core.telemetry
        )
    }

    func eventWriteContext(bypassConsent: Bool) async -> (DatadogContext, Writer)? {
        guard let core = core else {
            return nil
        }
        guard let storage = core.featureStore.storage(for: Feature.name) else {
            if core.get(feature: Feature.self) != nil {
                DD.logger.error(
                    "Failed to obtain Event Write Context for '\(Feature.name)' because it is not a `DatadogRemoteFeature`."
                )
                #if DEBUG
                assertionFailure("Obtaining Event Write Context for '\(Feature.name)' but it is not a `DatadogRemoteFeature`.")
                #endif
            }
            return nil
        }

        let context = await core.contextProvider.read()
        let writer = await storage.writer(for: bypassConsent ? .granted : context.trackingConsent)
        return (context, writer)
    }

    func context(_ block: @escaping @Sendable (DatadogContext) -> Void) {
        Task {
            guard let core = core else { return }
            let context = await core.contextProvider.read()
            block(context)
        }
    }

    var dataStore: DataStore {
        return (core != nil) ? store : NOPDataStore()
    }

    func send(message: FeatureMessage, else fallback: @escaping @Sendable () -> Void) {
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
    /// Creates a core context provider with the given configuration.
    static func create(
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
    ) -> DatadogContextProvider {
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

        let provider = DatadogContextProvider(context: context)

        let serverOffsetSource = ServerOffsetSource(provider: serverDateProvider)
        #if !os(macOS)
        let launchInfoSource = LaunchInfoSource(handler: appLaunchHandler, initialValue: launchInfo)
        #endif
        let nwPathSource = NWPathMonitorSource()
        #if os(iOS) && !targetEnvironment(macCatalyst) && !os(visionOS)
        let carrierInfoSource = CarrierInfoSource()
        #endif
        #if os(iOS) && !targetEnvironment(simulator)
        let batterySource = BatteryStatusSource(notificationCenter: notificationCenter, device: .current)
        let lowPowerSource = LowPowerModeSource(notificationCenter: notificationCenter, processInfo: processInfo)
        #endif
        #if os(iOS)
        let brightnessSource = BrightnessLevelSource(notificationCenter: notificationCenter)
        #endif
        let localeSource = LocaleInfoSource(initialLocale: locale, notificationCenter: notificationCenter)
        #if os(iOS) || os(tvOS)
        let appStateSource = ApplicationStateSource(
            appStateHistory: appStateHistory,
            notificationCenter: notificationCenter,
            dateProvider: dateProvider
        )
        #endif

        Task {
            await provider.subscribe(to: serverOffsetSource) { $0.serverTimeOffset = $1 }
            #if !os(macOS)
            await provider.subscribe(to: launchInfoSource) { $0.launchInfo = $1 }
            #endif
            await provider.subscribe(to: nwPathSource) { $0.networkConnectionInfo = $1 }
            #if os(iOS) && !targetEnvironment(macCatalyst) && !os(visionOS)
            await provider.subscribe(to: carrierInfoSource) { $0.carrierInfo = $1 }
            #endif
            #if os(iOS) && !targetEnvironment(simulator)
            await provider.subscribe(to: batterySource) { $0.batteryStatus = $1 }
            await provider.subscribe(to: lowPowerSource) { $0.isLowPowerModeEnabled = $1 }
            #endif
            #if os(iOS)
            await provider.subscribe(to: brightnessSource) { $0.brightnessLevel = $1 }
            #endif
            await provider.subscribe(to: localeSource) { $0.localeInfo = $1 }
            #if os(iOS) || os(tvOS)
            await provider.subscribe(to: appStateSource) { $0.applicationStateHistory = $1 }
            #endif
        }

        return provider
    }
}

extension DatadogCore {
    /// Flushes asynchronous operations related to events write, context and message bus propagation in this instance of the SDK.
    func flush() async {
        removeContext(ofType: LaunchReport.self)

        let flushables = featureStore.flushableFeatures

        for _ in 0..<5 {
            bus.flush()
            flushables.forEach { $0.flush() }
        }
    }
}

extension DatadogCore: Storage {
    func mostRecentModifiedFileAt(before: Date) throws -> Date? {
        let file = try directory.coreDirectory.mostRecentModifiedFile(before: before)
        return try file?.modifiedAt()
    }
}
// swiftlint:disable duplicate_imports
#if SPM_BUILD
    #if swift(>=6.0)
    @preconcurrency internal import DatadogPrivate
    #else
    @_implementationOnly import DatadogPrivate
    #endif
#endif
// swiftlint:enable duplicate_imports


nonisolated(unsafe) internal let registerObjcExceptionHandlerOnce: () -> Void = {
    ObjcException.rethrow = __dd_private_ObjcExceptionHandler.rethrow
    return {}
}()
