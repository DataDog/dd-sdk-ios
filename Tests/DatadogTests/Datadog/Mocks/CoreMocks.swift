/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogLogs
@testable import Datadog

// MARK: - Configuration Mocks

extension Datadog.Configuration {
    static func mockAny() -> Datadog.Configuration { .mockWith() }

    static func mockWith(
        rumApplicationID: String? = .mockAny(),
        clientToken: String = .mockAny(),
        environment: String = .mockAny(),
        loggingEnabled: Bool = false,
        tracingEnabled: Bool = false,
        rumEnabled: Bool = false,
        crashReportingPlugin: DDCrashReportingPluginType? = nil,
        datadogEndpoint: DatadogSite = .us1,
        customLogsEndpoint: URL? = nil,
        customTracesEndpoint: URL? = nil,
        customRUMEndpoint: URL? = nil,
        serviceName: String? = .mockAny(),
        firstPartyHosts: FirstPartyHosts? = nil,
        loggingSamplingRate: Float = 100.0,
        tracingSamplingRate: Float = 100.0,
        rumSessionsSamplingRate: Float = 100.0,
        rumUIKitViewsPredicate: UIKitRUMViewsPredicate? = nil,
        rumUIKitUserActionsPredicate: UIKitRUMUserActionsPredicate? = nil,
        rumLongTaskDurationThreshold: TimeInterval? = nil,
        rumResourceAttributesProvider: URLSessionRUMAttributesProvider? = nil,
        rumBackgroundEventTrackingEnabled: Bool = false,
        rumFrustrationSignalsTrackingEnabled: Bool = true,
        rumTelemetrySamplingRate: Float = 100.0,
        mobileVitalsFrequency: VitalsFrequency = .average,
        batchSize: BatchSize = .medium,
        uploadFrequency: UploadFrequency = .average,
        additionalConfiguration: [String: Any] = [:],
        proxyConfiguration: [AnyHashable: Any]? = nil,
        internalMonitoringClientToken: String? = nil
    ) -> Datadog.Configuration {
        return Datadog.Configuration(
            rumApplicationID: rumApplicationID,
            clientToken: clientToken,
            environment: environment,
            loggingEnabled: loggingEnabled,
            tracingEnabled: tracingEnabled,
            rumEnabled: rumEnabled,
            crashReportingPlugin: crashReportingPlugin,
            datadogEndpoint: datadogEndpoint,
            customLogsEndpoint: customLogsEndpoint,
            customTracesEndpoint: customTracesEndpoint,
            customRUMEndpoint: customRUMEndpoint,
            serviceName: serviceName,
            firstPartyHosts: firstPartyHosts,
            loggingSamplingRate: loggingSamplingRate,
            tracingSamplingRate: tracingSamplingRate,
            rumSessionsSamplingRate: rumSessionsSamplingRate,
            rumUIKitViewsPredicate: rumUIKitViewsPredicate,
            rumUIKitUserActionsPredicate: rumUIKitUserActionsPredicate,
            rumLongTaskDurationThreshold: rumLongTaskDurationThreshold,
            rumResourceAttributesProvider: rumResourceAttributesProvider,
            rumBackgroundEventTrackingEnabled: rumBackgroundEventTrackingEnabled,
            rumFrustrationSignalsTrackingEnabled: rumFrustrationSignalsTrackingEnabled,
            rumTelemetrySamplingRate: rumTelemetrySamplingRate,
            mobileVitalsFrequency: mobileVitalsFrequency,
            batchSize: batchSize,
            uploadFrequency: uploadFrequency,
            additionalConfiguration: additionalConfiguration,
            proxyConfiguration: proxyConfiguration
        )
    }
}

typealias BatchSize = Datadog.Configuration.BatchSize

extension BatchSize: CaseIterable {
    public static var allCases: [Self] { [.small, .medium, .large] }

    static func mockRandom() -> Self {
        allCases.randomElement()!
    }
}

typealias UploadFrequency = Datadog.Configuration.UploadFrequency

extension UploadFrequency: CaseIterable {
    public static var allCases: [Self] { [.frequent, .average, .rare] }

    static func mockRandom() -> Self {
        allCases.randomElement()!
    }
}

extension BundleType: CaseIterable {
    public static var allCases: [Self] { [.iOSApp, iOSAppExtension] }
}

extension Datadog.Configuration.RUMEndpoint {
    static func mockRandom() -> Self {
        return [.us1, .us3, .us5, .eu1, .ap1, .us1_fed, .us, .eu, .gov, .custom(url: "http://example.com/api/")].randomElement()!
    }
}

extension FeaturesConfiguration {
    static func mockAny() -> Self { mockWith() }

    static func mockWith(
        common: Common = .mockAny(),
        logging: Logging? = .mockAny(),
        rum: RUM? = .mockAny(),
        crashReporting: CrashReporting = .mockAny(),
        urlSessionAutoInstrumentation: URLSessionAutoInstrumentation? = .mockAny(),
        tracingEnabled: Bool = .mockAny()
    ) -> Self {
        return .init(
            common: common,
            logging: logging,
            rum: rum,
            urlSessionAutoInstrumentation: urlSessionAutoInstrumentation,
            crashReporting: crashReporting,
            tracingEnabled: tracingEnabled
        )
    }
}

extension FeaturesConfiguration.Common {
    static func mockAny() -> Self { mockWith() }

    static func mockWith(
        site: DatadogSite = .mockAny(),
        clientToken: String = .mockAny(),
        applicationName: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        applicationBundleIdentifier: String = .mockAny(),
        serviceName: String = .mockAny(),
        environment: String = .mockAny(),
        performance: PerformancePreset = .mockAny(),
        source: String = .mockAny(),
        variant: String? = nil,
        origin: String? = nil,
        sdkVersion: String = .mockAny(),
        proxyConfiguration: [AnyHashable: Any]? = nil,
        encryption: DataEncryption? = nil,
        serverDateProvider: ServerDateProvider? = nil,
        dateProvider: DateProvider = SystemDateProvider()
    ) -> Self {
        return .init(
            site: site,
            clientToken: clientToken,
            applicationName: applicationName,
            applicationVersion: applicationVersion,
            applicationBundleIdentifier: applicationBundleIdentifier,
            serviceName: serviceName,
            environment: environment,
            performance: performance,
            source: source,
            variant: variant,
            origin: origin,
            sdkVersion: sdkVersion,
            proxyConfiguration: proxyConfiguration,
            encryption: encryption,
            serverDateProvider: serverDateProvider,
            dateProvider: dateProvider
        )
    }
}

extension FeaturesConfiguration.Logging {
    static func mockAny() -> Self { mockWith() }

    static func mockWith(
        customURL: URL? = .mockAny(),
        logEventMapper: LogEventMapper? = nil,
        dateProvider: DateProvider = SystemDateProvider(),
        applicationBundleIdentifier: String = .mockAny(),
        remoteLoggingSampler: Sampler = Sampler(samplingRate: 100.0)
    ) -> Self {
        return .init(
            customURL: customURL,
            logEventMapper: logEventMapper,
            dateProvider: dateProvider,
            applicationBundleIdentifier: applicationBundleIdentifier,
            remoteLoggingSampler: remoteLoggingSampler
        )
    }
}

extension FeaturesConfiguration.RUM {
    static func mockAny() -> Self { mockWith() }

    static func mockWith(
        uploadURL: URL = .mockAny(),
        applicationID: String = .mockAny(),
        sessionSampler: Sampler = .mockKeepAll(),
        telemetrySampler: Sampler = .mockKeepAll(),
        uuidGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator(),
        viewEventMapper: RUMViewEventMapper? = nil,
        resourceEventMapper: RUMResourceEventMapper? = nil,
        actionEventMapper: RUMActionEventMapper? = nil,
        errorEventMapper: RUMErrorEventMapper? = nil,
        longTaskEventMapper: RUMLongTaskEventMapper? = nil,
        instrumentation: FeaturesConfiguration.RUM.Instrumentation? = nil,
        backgroundEventTrackingEnabled: Bool = false,
        frustrationTrackingEnabled: Bool = true,
        onSessionStart: @escaping RUMSessionListener = mockNoOpSessionListener(),
        firstPartyHosts: FirstPartyHosts = .init(),
        vitalsFrequency: TimeInterval? = 0.5,
        dateProvider: DateProvider = SystemDateProvider()
    ) -> Self {
        return .init(
            uploadURL: uploadURL,
            applicationID: applicationID,
            sessionSampler: sessionSampler,
            telemetrySampler: telemetrySampler,
            uuidGenerator: uuidGenerator,
            viewEventMapper: viewEventMapper,
            resourceEventMapper: resourceEventMapper,
            actionEventMapper: actionEventMapper,
            errorEventMapper: errorEventMapper,
            longTaskEventMapper: longTaskEventMapper,
            instrumentation: instrumentation,
            backgroundEventTrackingEnabled: backgroundEventTrackingEnabled,
            frustrationTrackingEnabled: frustrationTrackingEnabled,
            onSessionStart: onSessionStart,
            firstPartyHosts: firstPartyHosts,
            vitalsFrequency: vitalsFrequency,
            dateProvider: dateProvider
        )
    }
}

extension FeaturesConfiguration.CrashReporting {
    static func mockAny() -> Self {
        return mockWith()
    }

    static func mockWith(
        crashReportingPlugin: DDCrashReportingPluginType = CrashReportingPluginMock()
    ) -> Self {
        return .init(
            crashReportingPlugin: crashReportingPlugin
        )
    }
}

extension FeaturesConfiguration.URLSessionAutoInstrumentation {
    static func mockAny() -> Self { mockWith() }

    static func mockWith(
        userDefinedFirstPartyHosts: FirstPartyHosts = .init(),
        sdkInternalURLs: Set<String> = [],
        rumAttributesProvider: URLSessionRUMAttributesProvider? = nil,
        instrumentTracing: Bool = true,
        instrumentRUM: Bool = true,
        tracingSampler: Sampler = .mockKeepAll()
    ) -> Self {
        return .init(
            userDefinedFirstPartyHosts: userDefinedFirstPartyHosts,
            sdkInternalURLs: sdkInternalURLs,
            rumAttributesProvider: rumAttributesProvider,
            instrumentTracing: instrumentTracing,
            instrumentRUM: instrumentRUM,
            tracingSampler: tracingSampler
        )
    }
}

extension AppContext {
    static func mockAny() -> AppContext {
        return mockWith()
    }

    static func mockWith(
        bundleType: BundleType = .iOSApp,
        bundleIdentifier: String? = .mockAny(),
        bundleVersion: String? = .mockAny(),
        bundleName: String? = .mockAny(),
        processInfo: ProcessInfo = ProcessInfoMock()
    ) -> AppContext {
        return AppContext(
            bundleType: bundleType,
            bundleIdentifier: bundleIdentifier,
            bundleVersion: bundleVersion,
            bundleName: bundleName,
            processInfo: processInfo
        )
    }
}

struct DataEncryptionMock: DataEncryption {
    let enc: (Data) throws -> Data
    let dec: (Data) throws -> Data

    init(
        encrypt: @escaping (Data) throws -> Data = { $0 },
        decrypt: @escaping (Data) throws -> Data = { $0 }
    ) {
        enc = encrypt
        dec = decrypt
    }

    func encrypt(data: Data) throws -> Data { try enc(data) }
    func decrypt(data: Data) throws -> Data { try dec(data) }
}

class ServerDateProviderMock: ServerDateProvider {
    private var update: (TimeInterval) -> Void = { _ in }

    var offset: TimeInterval = .zero {
        didSet { update(offset) }
    }

    func synchronize(update: @escaping (TimeInterval) -> Void) {
        self.update = update
    }
}

// MARK: - PerformancePreset Mocks

struct StoragePerformanceMock: StoragePerformancePreset {
    let maxFileSize: UInt64
    let maxDirectorySize: UInt64
    let maxFileAgeForWrite: TimeInterval
    let minFileAgeForRead: TimeInterval
    let maxFileAgeForRead: TimeInterval
    let maxObjectsInFile: Int
    let maxObjectSize: UInt64

    static let noOp = StoragePerformanceMock(
        maxFileSize: 0,
        maxDirectorySize: 0,
        maxFileAgeForWrite: 0,
        minFileAgeForRead: 0,
        maxFileAgeForRead: 0,
        maxObjectsInFile: 0,
        maxObjectSize: 0
    )

    static let readAllFiles = StoragePerformanceMock(
        maxFileSize: .max,
        maxDirectorySize: .max,
        maxFileAgeForWrite: 0,
        minFileAgeForRead: -1, // make all files eligible for read
        maxFileAgeForRead: .distantFuture, // make all files eligible for read
        maxObjectsInFile: .max,
        maxObjectSize: .max
    )

    static let writeEachObjectToNewFileAndReadAllFiles = StoragePerformanceMock(
        maxFileSize: .max,
        maxDirectorySize: .max,
        maxFileAgeForWrite: 0, // always return new file for writing
        minFileAgeForRead: readAllFiles.minFileAgeForRead,
        maxFileAgeForRead: readAllFiles.maxFileAgeForRead,
        maxObjectsInFile: 1, // write each data to new file
        maxObjectSize: .max
    )
}

struct UploadPerformanceMock: UploadPerformancePreset {
    let initialUploadDelay: TimeInterval
    let minUploadDelay: TimeInterval
    let maxUploadDelay: TimeInterval
    let uploadDelayChangeRate: Double

    static let noOp = UploadPerformanceMock(
        initialUploadDelay: .distantFuture,
        minUploadDelay: .distantFuture,
        maxUploadDelay: .distantFuture,
        uploadDelayChangeRate: 0
    )

    /// Optimized for performing very fast uploads in unit tests.
    static let veryQuick = UploadPerformanceMock(
        initialUploadDelay: 0.05,
        minUploadDelay: 0.05,
        maxUploadDelay: 0.05,
        uploadDelayChangeRate: 0
    )

    /// Optimized for performing very fast first upload and then changing to unrealistically long intervals.
    static let veryQuickInitialUpload = UploadPerformanceMock(
        initialUploadDelay: 0.05,
        minUploadDelay: 60,
        maxUploadDelay: 60,
        uploadDelayChangeRate: 60 / 0.05
    )
}

extension BundleType: AnyMockable, RandomMockable {
    public static func mockAny() -> BundleType {
        return .iOSApp
    }

    public static func mockRandom() -> BundleType {
        return [.iOSApp, .iOSAppExtension].randomElement()!
    }
}

extension PerformancePreset: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        PerformancePreset(batchSize: .medium, uploadFrequency: .average, bundleType: .iOSApp)
    }

    public static func mockRandom() -> Self {
        PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .mockRandom(), bundleType: .mockRandom())
    }

    static func combining(storagePerformance storage: StoragePerformanceMock, uploadPerformance upload: UploadPerformanceMock) -> Self {
        PerformancePreset(
            maxFileSize: storage.maxFileSize,
            maxDirectorySize: storage.maxDirectorySize,
            maxFileAgeForWrite: storage.maxFileAgeForWrite,
            minFileAgeForRead: storage.minFileAgeForRead,
            maxFileAgeForRead: storage.maxFileAgeForRead,
            maxObjectsInFile: storage.maxObjectsInFile,
            maxObjectSize: storage.maxObjectSize,
            initialUploadDelay: upload.initialUploadDelay,
            minUploadDelay: upload.minUploadDelay,
            maxUploadDelay: upload.maxUploadDelay,
            uploadDelayChangeRate: upload.uploadDelayChangeRate
        )
    }
}

extension FeatureStorage {
    static func mockNoOp() -> FeatureStorage {
        return FeatureStorage(
            featureName: .mockAny(),
            queue: DispatchQueue(label: "nop"),
            directories: temporaryFeatureDirectories,
            authorizedFilesOrchestrator: NOPFilesOrchestrator(),
            unauthorizedFilesOrchestrator: NOPFilesOrchestrator(),
            encryption: nil
        )
    }
}

extension FeatureUpload {
    static func mockNoOp() -> FeatureUpload {
        return FeatureUpload(uploader: NOPDataUploadWorker())
    }
}

class NOPReader: Reader {
    func readNextBatch() -> Batch? { nil }
    func markBatchAsRead(_ batch: Batch) {}
}

internal class NOPFilesOrchestrator: FilesOrchestratorType {
    struct NOPFile: WritableFile, ReadableFile {
        var name: String = .mockAny()
        func size() throws -> UInt64 { .mockAny() }
        func append(data: Data) throws {}
        func stream() throws -> InputStream { InputStream() }
        func delete() throws { }
    }

    var performance: StoragePerformancePreset { StoragePerformanceMock.noOp }

    func getNewWritableFile(writeSize: UInt64) throws -> WritableFile { NOPFile() }
    func getWritableFile(writeSize: UInt64) throws -> WritableFile { NOPFile() }
    func getReadableFile(excludingFilesNamed excludedFileNames: Set<String>) -> ReadableFile? { NOPFile() }
    func delete(readableFile: ReadableFile) { }

    var ignoreFilesAgeWhenReading = false
}

extension DataFormat {
    static func mockAny() -> DataFormat {
        return mockWith()
    }

    static func mockWith(
        prefix: String = .mockAny(),
        suffix: String = .mockAny(),
        separator: Character = .mockAny()
    ) -> DataFormat {
        return DataFormat(
            prefix: prefix,
            suffix: suffix,
            separator: separator
        )
    }
}

class AppStateListenerMock: AppStateListening, AnyMockable {
    let history: AppStateHistory

    required init(history: AppStateHistory) {
        self.history = history
    }

    static func mockAny() -> Self {
        return mockAppInForeground(since: .mockDecember15th2019At10AMUTC())
    }

    static func mockAppInForeground(since date: Date = Date()) -> Self {
        return .init(
            history: .mockAppInForeground(since: date)
        )
    }

    static func mockAppInBackground(since date: Date = Date()) -> Self {
        return .init(
            history: .mockAppInBackground(since: date)
        )
    }

    static func mockRandom(since date: Date = Date()) -> Self {
        return .init(
            history: .mockRandom(since: date)
        )
    }

    func subscribe<Observer: AppStateHistoryObserver>(_ subscriber: Observer) where Observer.ObservedValue == AppStateHistory {}
}

extension UserInfoProvider {
    static func mockAny() -> UserInfoProvider {
        return mockWith()
    }

    static func mockWith(userInfo: UserInfo = .mockAny()) -> UserInfoProvider {
        let provider = UserInfoProvider()
        provider.value = userInfo
        return provider
    }
}

extension HTTPClient {
    static func mockAny() -> HTTPClient {
        return HTTPClient(session: .mockAny())
    }
}

class NOPDataUploadWorker: DataUploadWorkerType {
    func flushSynchronously() {}
    func cancelSynchronously() {}
}

struct DataUploaderMock: DataUploaderType {
    let uploadStatus: DataUploadStatus

    var onUpload: (() throws -> Void)? = nil

    func upload(events: [Data], context: DatadogContext) throws -> DataUploadStatus {
        try onUpload?()
        return uploadStatus
    }
}

extension DataUploadStatus: RandomMockable {
    public static func mockRandom() -> DataUploadStatus {
        return DataUploadStatus(
            needsRetry: .random(),
            userDebugDescription: .mockRandom(),
            error: nil
        )
    }

    static func mockWith(
        needsRetry: Bool = .mockAny(),
        userDebugDescription: String = .mockAny(),
        error: DataUploadError? = nil
    ) -> DataUploadStatus {
        return DataUploadStatus(
            needsRetry: needsRetry,
            userDebugDescription: userDebugDescription,
            error: error
        )
    }
}

extension BatteryStatus.State {
    static func mockRandom(within cases: [BatteryStatus.State] = [.unknown, .unplugged, .charging, .full]) -> BatteryStatus.State {
        return cases.randomElement()!
    }
}

extension ValuePublisher: AnyMockable where Value: AnyMockable {
    public static func mockAny() -> Self {
        return .init(initialValue: .mockAny())
    }
}

extension ValuePublisher: RandomMockable where Value: RandomMockable {
    public static func mockRandom() -> Self {
        return .init(initialValue: .mockRandom())
    }
}

extension ValuePublisher {
    /// Publishes `newValue` using `publishSync(:_)` or `publishAsync(:_)`.
    func publishSyncOrAsync(_ newValue: Value) {
        if Bool.random() {
            publishSync(newValue)
        } else {
            publishAsync(newValue)
        }
    }
}

internal class ValueObserverMock<Value>: ValueObserver {
    typealias ObservedValue = Value

    private(set) var onValueChange: ((Value, Value) -> Void)?
    private(set) var lastChange: (oldValue: Value, newValue: Value)?

    init(onValueChange: ((Value, Value) -> Void)? = nil) {
        self.onValueChange = onValueChange
    }

    func onValueChanged(oldValue: Value, newValue: Value) {
        lastChange = (oldValue, newValue)
        onValueChange?(oldValue, newValue)
    }
}

class MockHostsSanitizer: HostsSanitizing {
    private(set) var sanitizations = [(hosts: Set<String>, warningMessage: String)]()
    func sanitized(hosts: Set<String>, warningMessage: String) -> Set<String> {
        sanitizations.append((hosts: hosts, warningMessage: warningMessage))
        return hosts
    }

    func sanitized(
        hostsWithTracingHeaderTypes: [String: Set<TracingHeaderType>],
        warningMessage: String
    ) -> [String: Set<TracingHeaderType>] {
        sanitizations.append((hosts: Set(hostsWithTracingHeaderTypes.keys), warningMessage: warningMessage))
        return hostsWithTracingHeaderTypes
    }
}
