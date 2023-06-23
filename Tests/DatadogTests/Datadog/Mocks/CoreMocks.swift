/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
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
        datadogEndpoint: DatadogEndpoint? = nil,
        customLogsEndpoint: URL? = nil,
        customTracesEndpoint: URL? = nil,
        customRUMEndpoint: URL? = nil,
        logsEndpoint: LogsEndpoint = .us1,
        tracesEndpoint: TracesEndpoint = .us1,
        rumEndpoint: RUMEndpoint = .us1,
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
            logsEndpoint: logsEndpoint,
            tracesEndpoint: tracesEndpoint,
            rumEndpoint: rumEndpoint,
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

extension Sampler: AnyMockable, RandomMockable {
    public static func mockAny() -> Sampler {
        return .init(samplingRate: 50)
    }

    public static func mockRandom() -> Sampler {
        return .init(samplingRate: .random(in: (0.0...100.0)))
    }

    static func mockKeepAll() -> Sampler {
        return .init(samplingRate: 100)
    }

    static func mockRejectAll() -> Sampler {
        return .init(samplingRate: 0)
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

extension Datadog.Configuration.LogsEndpoint {
    static func mockRandom() -> Self {
        return [.us1, .us3, .us5, .eu1, .ap1, .us1_fed, .us, .eu, .gov, .custom(url: "http://example.com/api/")].randomElement()!
    }
}

extension Datadog.Configuration.TracesEndpoint {
    static func mockRandom() -> Self {
        return [.us1, .us3, .us5, .eu1, .ap1, .us1_fed, .us, .eu, .gov, .custom(url: "http://example.com/api/")].randomElement()!
    }
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
        tracing: Tracing? = .mockAny(),
        rum: RUM? = .mockAny(),
        crashReporting: CrashReporting = .mockAny(),
        urlSessionAutoInstrumentation: URLSessionAutoInstrumentation? = .mockAny()
    ) -> Self {
        return .init(
            common: common,
            logging: logging,
            tracing: tracing,
            rum: rum,
            urlSessionAutoInstrumentation: urlSessionAutoInstrumentation,
            crashReporting: crashReporting
        )
    }
}

extension FeaturesConfiguration.Common {
    static func mockAny() -> Self { mockWith() }

    static func mockWith(
        site: DatadogSite? = .mockAny(),
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
        uploadURL: URL = .mockAny(),
        logEventMapper: LogEventMapper? = nil,
        dateProvider: DateProvider = SystemDateProvider(),
        applicationBundleIdentifier: String = .mockAny(),
        remoteLoggingSampler: Sampler = Sampler(samplingRate: 100.0)
    ) -> Self {
        return .init(
            uploadURL: uploadURL,
            logEventMapper: logEventMapper,
            dateProvider: dateProvider,
            applicationBundleIdentifier: applicationBundleIdentifier,
            remoteLoggingSampler: remoteLoggingSampler
        )
    }
}

extension FeaturesConfiguration.Tracing {
    static func mockAny() -> Self { mockWith() }

    static func mockWith(
        uploadURL: URL = .mockAny(),
        uuidGenerator: TracingUUIDGenerator = DefaultTracingUUIDGenerator(),
        spanEventMapper: SpanEventMapper? = nil,
        dateProvider: DateProvider = SystemDateProvider()
    ) -> Self {
        return .init(
            uploadURL: uploadURL,
            uuidGenerator: uuidGenerator,
            spanEventMapper: spanEventMapper,
            dateProvider: dateProvider
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
        configurationTelemetrySampler: Sampler = .mockKeepAll(),
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
            configurationTelemetrySampler: configurationTelemetrySampler,
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

/// `DateProvider` mock returning consecutive dates in custom intervals, starting from given reference date.
class RelativeDateProvider: DateProvider {
    private(set) var date: Date
    internal let timeInterval: TimeInterval
    private let queue = DispatchQueue(label: "queue-RelativeDateProvider-\(UUID().uuidString)")

    private init(date: Date, timeInterval: TimeInterval) {
        self.date = date
        self.timeInterval = timeInterval
    }

    convenience init(using date: Date = Date()) {
        self.init(date: date, timeInterval: 0)
    }

    convenience init(startingFrom referenceDate: Date = Date(), advancingBySeconds timeInterval: TimeInterval = 0) {
        self.init(date: referenceDate, timeInterval: timeInterval)
    }

    /// Returns current date and advances next date by `timeInterval`.
    var now: Date {
        defer {
            queue.async {
                self.date.addTimeInterval(self.timeInterval)
            }
        }
        return queue.sync {
            return date
        }
    }

    /// Pushes time forward by given number of seconds.
    func advance(bySeconds seconds: TimeInterval) {
        queue.async {
            self.date = self.date.addingTimeInterval(seconds)
        }
    }
}

extension AppState: AnyMockable, RandomMockable {
    public static func mockAny() -> AppState {
        return .active
    }

    public static func mockRandom() -> AppState {
        return [.active, .inactive, .background].randomElement()!
    }

    static func mockRandom(runningInForeground: Bool) -> AppState {
        return runningInForeground ? [.active, .inactive].randomElement()! : .background
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

    func upload(events: [Event], context: DatadogContext) throws -> DataUploadStatus {
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

extension DDError: AnyMockable, RandomMockable {
    public static func mockAny() -> DDError {
        return DDError(
            type: .mockAny(),
            message: .mockAny(),
            stack: .mockAny()
        )
    }

    public static func mockRandom() -> DDError {
        return DDError(
            type: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom()
        )
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

// MARK: - Global Dependencies Mocks

/// Mock which can be used to intercept messages printed by `developerLogger` or
/// `userLogger` by overwriting `Datadog.consolePrint` function:
///
///     let printFunction = PrintFunctionMock()
///     consolePrint = printFunction.print
///
class PrintFunctionMock {
    private(set) var printedMessages: [String] = []
    var printedMessage: String? { printedMessages.last }

    func print(message: String) {
        printedMessages.append(message)
    }

    func reset() {
        printedMessages = []
    }
}

class CoreLoggerMock: CoreLogger {
    private let queue = DispatchQueue(label: "core-logger-mock")
    private(set) var recordedLogs: [(level: CoreLoggerLevel, message: String, error: Error?)] = []

    // MARK: - CoreLogger

    func log(_ level: CoreLoggerLevel, message: @autoclosure () -> String, error: Error?) {
        let newLog = (level, message(), error)
        queue.async { self.recordedLogs.append(newLog) }
    }

    func reset() {
        queue.async { self.recordedLogs = [] }
    }

    // MARK: - Matching

    typealias RecordedLog = (message: String, error: DDError?)

    private func recordedLogs(ofLevel level: CoreLoggerLevel) -> [RecordedLog] {
        return queue.sync {
            recordedLogs
                .filter({ $0.level == level })
                .map { ($0.message, $0.error.map({ DDError(error: $0) })) }
        }
    }

    var debugLogs: [RecordedLog] { recordedLogs(ofLevel: .debug) }
    var warnLogs: [RecordedLog] { recordedLogs(ofLevel: .warn) }
    var errorLogs: [RecordedLog] { recordedLogs(ofLevel: .error) }
    var criticalLogs: [RecordedLog] { recordedLogs(ofLevel: .critical) }

    var debugLog: RecordedLog? { debugLogs.last }
    var warnLog: RecordedLog? { warnLogs.last }
    var errorLog: RecordedLog? { errorLogs.last }
    var criticalLog: RecordedLog? { criticalLogs.last }
}

/// `Telemtry` recording received telemetry.
class TelemetryMock: Telemetry, CustomStringConvertible {
    private(set) var debugs: [String] = []
    private(set) var errors: [(message: String, kind: String?, stack: String?)] = []
    private(set) var configurations: [FeaturesConfiguration] = []
    private(set) var description: String = "Telemetry logs:"

    func debug(id: String, message: String) {
        debugs.append(message)
        description.append("\n- [debug] \(message)")
    }

    func error(id: String, message: String, kind: String?, stack: String?) {
        errors.append((message: message, kind: kind, stack: stack))
        description.append("\n - [error] \(message), kind: \(kind ?? "nil"), stack: \(stack ?? "nil")")
    }

    func configuration(configuration: FeaturesConfiguration) {
        configurations.append(configuration)
        description.append("\n - [configuration] \(configuration)")
    }
}

extension DD {
    /// Syntactic sugar for patching the `dd` bundle by replacing `logger`.
    ///
    /// ```
    /// let dd = DD.mockWith(logger: CoreLoggerMock())
    /// defer { dd.reset() }
    /// ```
    static func mockWith<CL: CoreLogger>(logger: CL) -> DDMock<CL, TelemetryMock> {
        let mock = DDMock(
            oldLogger: DD.logger,
            oldTelemetry: DD.telemetry,
            logger: logger,
            telemetry: TelemetryMock()
        )
        DD.logger = logger
        return mock
    }

    /// Syntactic sugar for patching the `dd` bundle by replacing `telemetry`.
    ///
    /// ```
    /// let dd = DD.mockWith(telemetry: TelemetryMock())
    /// defer { dd.reset() }
    /// ```
    static func mockWith<TM: Telemetry>(telemetry: TM) -> DDMock<CoreLoggerMock, TM> {
        let mock = DDMock(
            oldLogger: DD.logger,
            oldTelemetry: DD.telemetry,
            logger: CoreLoggerMock(),
            telemetry: telemetry
        )
        DD.telemetry = telemetry
        return mock
    }
}

struct DDMock<CL: CoreLogger, TM: Telemetry> {
    let oldLogger: CoreLogger
    let oldTelemetry: Telemetry

    let logger: CL
    let telemetry: TM

    func reset() {
        DD.logger = oldLogger
        DD.telemetry = oldTelemetry
    }
}
