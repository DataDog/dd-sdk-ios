/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// MARK: - Configuration Mocks

extension TrackingConsent {
    static func mockRandom() -> TrackingConsent {
        return [.granted, .notGranted, .pending].randomElement()!
    }

    static func mockRandom(otherThan consent: TrackingConsent? = nil) -> TrackingConsent {
        while true {
            let randomConsent: TrackingConsent = .mockRandom()
            if randomConsent != consent {
                return randomConsent
            }
        }
    }
}

extension ConsentProvider {
    static func mockAny() -> ConsentProvider {
        return ConsentProvider(initialConsent: .mockRandom())
    }
}

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
        firstPartyHosts: Set<String>? = nil,
        tracingSamplingRate: Float = 100.0,
        rumSessionsSamplingRate: Float = 100.0,
        rumUIKitViewsPredicate: UIKitRUMViewsPredicate? = nil,
        rumUIKitUserActionsPredicate: UIKitRUMUserActionsPredicate? = nil,
        rumLongTaskDurationThreshold: TimeInterval? = nil,
        rumResourceAttributesProvider: URLSessionRUMAttributesProvider? = nil,
        rumBackgroundEventTrackingEnabled: Bool = false,
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
            tracingSamplingRate: tracingSamplingRate,
            rumSessionsSamplingRate: rumSessionsSamplingRate,
            rumUIKitViewsPredicate: rumUIKitViewsPredicate,
            rumUIKitUserActionsPredicate: rumUIKitUserActionsPredicate,
            rumLongTaskDurationThreshold: rumLongTaskDurationThreshold,
            rumResourceAttributesProvider: rumResourceAttributesProvider,
            rumBackgroundEventTrackingEnabled: rumBackgroundEventTrackingEnabled,
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
    static func mockAny() -> Sampler {
        return .init(samplingRate: 50)
    }

    static func mockRandom() -> Sampler {
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

extension Datadog.Configuration.DatadogEndpoint: AnyMockable, RandomMockable {
    static func mockAny() -> Datadog.Configuration.DatadogEndpoint {
        return .us1
    }

    static func mockRandom() -> Self {
        return [.us1, .us3, .eu1, .us1_fed].randomElement()!
    }
}

extension Datadog.Configuration.LogsEndpoint {
    static func mockRandom() -> Self {
        return [.us1, .us3, .eu1, .us1_fed, .us, .eu, .gov, .custom(url: "http://example.com/api/")].randomElement()!
    }
}

extension Datadog.Configuration.TracesEndpoint {
    static func mockRandom() -> Self {
        return [.us1, .us3, .eu1, .us1_fed, .us, .eu, .gov, .custom(url: "http://example.com/api/")].randomElement()!
    }
}

extension Datadog.Configuration.RUMEndpoint {
    static func mockRandom() -> Self {
        return [.us1, .us3, .eu1, .us1_fed, .us, .eu, .gov, .custom(url: "http://example.com/api/")].randomElement()!
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
        performance: PerformancePreset = .init(batchSize: .medium, uploadFrequency: .average, bundleType: .iOSApp),
        source: String = .mockAny(),
        origin: String? = nil,
        sdkVersion: String = .mockAny(),
        proxyConfiguration: [AnyHashable: Any]? = nil,
        encryption: DataEncryption? = nil
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
            origin: origin,
            sdkVersion: sdkVersion,
            proxyConfiguration: proxyConfiguration,
            encryption: encryption
        )
    }
}

extension FeaturesConfiguration.Logging {
    static func mockAny() -> Self { mockWith() }

    static func mockWith(
        uploadURL: URL = .mockAny(),
        logEventMapper: LogEventMapper? = nil
    ) -> Self {
        return .init(
            uploadURL: uploadURL,
            logEventMapper: logEventMapper
        )
    }
}

extension FeaturesConfiguration.Tracing {
    static func mockAny() -> Self { mockWith() }

    static func mockWith(
        uploadURL: URL = .mockAny(),
        uuidGenerator: TracingUUIDGenerator = DefaultTracingUUIDGenerator(),
        spanEventMapper: SpanEventMapper? = nil
    ) -> Self {
        return .init(
            uploadURL: uploadURL,
            uuidGenerator: uuidGenerator,
            spanEventMapper: spanEventMapper
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
        onSessionStart: @escaping RUMSessionListener = mockNoOpSessionListener(),
        firstPartyHosts: Set<String> = [],
        vitalsFrequency: TimeInterval? = 0.5
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
            onSessionStart: onSessionStart,
            firstPartyHosts: firstPartyHosts,
            vitalsFrequency: vitalsFrequency
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
        userDefinedFirstPartyHosts: Set<String> = [],
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

extension PerformancePreset {
    static func combining(storagePerformance storage: StoragePerformanceMock, uploadPerformance upload: UploadPerformanceMock) -> PerformancePreset {
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

// MARK: - Features Common Mocks

extension FeaturesCommonDependencies {
    static func mockAny() -> FeaturesCommonDependencies {
        return .mockWith()
    }

    /// Mocks features common dependencies.
    /// Default values describe the environment setup where data can be uploaded to the server (device is online and battery is full).
    static func mockWith(
        consentProvider: ConsentProvider = ConsentProvider(initialConsent: .granted),
        performance: PerformancePreset = .combining(
            storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
            uploadPerformance: .veryQuick
        ),
        deviceInfo: DeviceInfo = .mockAny(),
        batteryStatusProvider: BatteryStatusProviderType = BatteryStatusProviderMock.mockAny(),
        sdkInitDate: Date = Date(),
        dateProvider: DateProvider = SystemDateProvider(),
        dateCorrector: DateCorrector = DateCorrectorMock(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockWith(
            networkConnectionInfo: .mockWith(
                reachability: .yes, // so it always meets the upload condition
                availableInterfaces: [.wifi],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: true,
                isConstrained: false // so it always meets the upload condition
            )
        ),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny(),
        launchTimeProvider: LaunchTimeProviderType = LaunchTimeProviderMock.mockAny(),
        appStateListener: AppStateListening = AppStateListenerMock.mockAny(),
        encryption: DataEncryption? = nil
    ) -> FeaturesCommonDependencies {
        let httpClient: HTTPClient

        if let activeServer = ServerMock.activeInstance {
            httpClient = HTTPClient(session: activeServer.getInterceptedURLSession())
        } else {
            class AssertedHTTPClient: HTTPClient {
                // swiftlint:disable:next unavailable_function
                override func send(request: URLRequest, completion: @escaping (Result<HTTPURLResponse, Error>) -> Void) {
                    preconditionFailure(
                        """
                        ⚠️ Request to \(request.url?.absoluteString ?? "null") was sent but there is no `ServerMock` instance set up for its interception.
                        All unit tests must be configured to either send data to mocked `FeatureStorage` (`XYZFeature.mockByRecordingXYZ(...)`)
                        or use `ServerMock` instance and `serverMock.getInterceptedURLSession()` for requests interception.
                        """
                    )
                }
            }

            httpClient = AssertedHTTPClient()
        }

        return FeaturesCommonDependencies(
            consentProvider: consentProvider,
            performance: performance,
            httpClient: httpClient,
            deviceInfo: deviceInfo,
            batteryStatusProvider: batteryStatusProvider,
            sdkInitDate: sdkInitDate,
            dateProvider: dateProvider,
            dateCorrector: dateCorrector,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider,
            launchTimeProvider: launchTimeProvider,
            appStateListener: appStateListener,
            encryption: encryption
        )
    }

    /// Creates new instance of `FeaturesCommonDependencies` by replacing individual dependencies.
    func replacing(
        consentProvider: ConsentProvider? = nil,
        performance: PerformancePreset? = nil,
        httpClient: HTTPClient? = nil,
        deviceInfo: DeviceInfo? = nil,
        batteryStatusProvider: BatteryStatusProviderType? = nil,
        sdkInitDate: Date? = nil,
        dateProvider: DateProvider? = nil,
        dateCorrector: DateCorrector? = nil,
        userInfoProvider: UserInfoProvider? = nil,
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType? = nil,
        carrierInfoProvider: CarrierInfoProviderType? = nil,
        launchTimeProvider: LaunchTimeProviderType? = nil,
        appStateListener: AppStateListening? = nil,
        encryption: DataEncryption? = nil
    ) -> FeaturesCommonDependencies {
        return FeaturesCommonDependencies(
            consentProvider: consentProvider ?? self.consentProvider,
            performance: performance ?? self.performance,
            httpClient: httpClient ?? self.httpClient,
            deviceInfo: deviceInfo ?? self.deviceInfo,
            batteryStatusProvider: batteryStatusProvider ?? self.batteryStatusProvider,
            sdkInitDate: sdkInitDate ?? self.sdkInitDate,
            dateProvider: dateProvider ?? self.dateProvider,
            dateCorrector: dateCorrector ?? self.dateCorrector,
            userInfoProvider: userInfoProvider ?? self.userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider ?? self.networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider ?? self.carrierInfoProvider,
            launchTimeProvider: launchTimeProvider ?? self.launchTimeProvider,
            appStateListener: appStateListener ?? self.appStateListener,
            encryption: encryption ?? self.encryption
        )
    }
}

extension FeatureStorage {
    static func mockNoOp() -> FeatureStorage {
        return FeatureStorage(
            writer: NoOpFileWriter(),
            reader: NoOpFileReader(),
            arbitraryAuthorizedWriter: NoOpFileWriter(),
            dataOrchestrator: NoOpDataOrchestrator()
        )
    }
}

extension FeatureUpload {
    static func mockNoOp() -> FeatureUpload {
        return FeatureUpload(uploader: NoOpDataUploadWorker())
    }
}

class FileWriterMock: Writer {
    /// Recorded events.
    internal private(set) var events: [Encodable] = []

    /// Adds an `Encodable` event to the events stack.
    ///
    /// - Parameter value: The event value to record.
    func write<T>(value: T) where T: Encodable {
        events.append(value)
    }

    /// Returns all events of the given type.
    ///
    /// - Parameter type: The event type to retrieve.
    /// - Returns: A list of event of the give type.
    func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable {
        events.compactMap { $0 as? T }
    }
}

struct NoOpDataOrchestrator: DataOrchestratorType {
    func deleteAllData() {}
}

class NoOpFileWriter: AsyncWriter {
    var queue: DispatchQueue { DispatchQueue(label: .mockRandom()) }
    func write<T>(value: T) where T: Encodable {}
    func flushAndCancelSynchronously() {}
}

class NoOpFileReader: SyncReader {
    var queue: DispatchQueue { DispatchQueue(label: .mockRandom()) }
    func readNextBatch() -> Batch? { return nil }
    func markBatchAsRead(_ batch: Batch) {}
    func markAllFilesAsReadable() {}
}

/// `AsyncWriter` stub which records events in-memory and allows reading their data back.
internal class InMemoryWriter: AsyncWriter {
    let queue = DispatchQueue(label: "com.datadoghq.InMemoryWriter-\(UUID().uuidString)")

    private let encoder: JSONEncoder = .default()
    private var events: [Data] = []

    func write<T>(value: T) where T: Encodable {
        queue.async {
            do {
                let eventData = try self.encoder.encode(value)
                self.events.append(eventData)
                self.waitAndReturnEventsDataExpectation?.fulfill()
            } catch {
                assertionFailure("Failed to encode event: \(value)")
            }
        }
    }

    func flushAndCancelSynchronously() {
        queue.sync {}
    }

    // MARK: - Retrieving Recorded Data

    private var waitAndReturnEventsDataExpectation: XCTestExpectation?

    /// Waits until given number of events is written and returns data for these events.
    /// Passing no `timeout` will result with picking the recommended timeout for unit tests.
    func waitAndReturnEventsData(count: UInt, timeout: TimeInterval? = nil, file: StaticString = #file, line: UInt = #line) -> [Data] {
        precondition(waitAndReturnEventsDataExpectation == nil, "The `InMemoryWriter` is already waiting on `waitAndReturnEventsData`.")

        let expectation = XCTestExpectation(description: "Record \(count) events.")
        if count > 0 {
            expectation.expectedFulfillmentCount = Int(count)
        } else {
            expectation.isInverted = true
        }

        queue.sync {
            self.waitAndReturnEventsDataExpectation = expectation
            self.events.forEach { _ in expectation.fulfill() } // fulfill already recorded events
        }

        let recommendedTimeout = Double(max(1, count)) * 1 // 1s for each event
        let timeout = timeout ?? recommendedTimeout
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        switch result {
        case .completed:
            break
        case .incorrectOrder, .interrupted:
            fatalError("Can't happen.")
        case .timedOut:
            XCTFail("Exceeded timeout of \(timeout)s with recording \(events.count) out of \(count) expected events.", file: file, line: line)
            return queue.sync { events }
        case .invertedFulfillment:
            XCTFail("\(events.count) batches were read, but not expected.", file: file, line: line)
            return queue.sync { events }
        @unknown default:
            fatalError()
        }

        return queue.sync { events }
    }
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

/// `DateCorrector` mock, correcting dates by adding predefined offset.
class DateCorrectorMock: DateCorrector {
    var offset: TimeInterval

    init(offset: TimeInterval = 0) {
        self.offset = offset
    }
}

struct LaunchTimeProviderMock: LaunchTimeProviderType {
    let launchTime: TimeInterval
    let isActivePrewarm: Bool
}

extension LaunchTimeProviderMock {
    static func mockAny() -> LaunchTimeProviderMock {
        return mockWith(launchTime: 0, isActivePrewarm: false)
    }

    static func mockWith(launchTime: TimeInterval, isActivePrewarm: Bool = false) -> LaunchTimeProviderMock {
        return LaunchTimeProviderMock(launchTime: launchTime, isActivePrewarm: isActivePrewarm)
    }

    static func mockRandom(launchTime: TimeInterval = .mockRandom(), isActivePrewarm: Bool = .random()) -> LaunchTimeProviderMock {
        return mockWith(launchTime: launchTime, isActivePrewarm: isActivePrewarm)
    }
}

extension AppState: AnyMockable, RandomMockable {
    static func mockAny() -> AppState {
        return .active
    }

    static func mockRandom() -> AppState {
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
            history: .init(initialSnapshot: .init(state: .active, date: date), recentDate: date)
        )
    }

    static func mockAppInBackground(since date: Date = Date()) -> Self {
        return .init(
            history: .init(initialSnapshot: .init(state: .background, date: date), recentDate: date)
        )
    }

    static func mockRandom(since date: Date = Date()) -> Self {
        return Bool.random() ? mockAppInForeground(since: date) : mockAppInBackground(since: date)
    }

    func subscribe<Observer: AppStateHistoryObserver>(_ subscriber: Observer) where Observer.ObservedValue == AppStateHistory {}
}

extension UserInfo: AnyMockable, RandomMockable {
    static func mockAny() -> UserInfo {
        return mockEmpty()
    }

    static func mockEmpty() -> UserInfo {
        return UserInfo(id: nil, name: nil, email: nil, extraInfo: [:])
    }

    static func mockRandom() -> UserInfo {
        return .init(
            id: .mockRandom(),
            name: .mockRandom(),
            email: .mockRandom(),
            extraInfo: mockRandomAttributes()
        )
    }
}

extension UserInfo: EquatableInTests {}

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

extension RequestBuilder.QueryItem: RandomMockable, AnyMockable {
    static func mockRandom() -> RequestBuilder.QueryItem {
        let all: [RequestBuilder.QueryItem] = [
            .ddsource(source: .mockRandom()),
            .ddtags(tags: .mockRandom()),
        ]
        return all.randomElement()!
    }

    static func mockAny() -> RequestBuilder.QueryItem {
        return .ddsource(source: .mockRandom(among: .alphanumerics))
    }
}

extension RequestBuilder.HTTPHeader: RandomMockable, AnyMockable {
    static func mockRandom() -> RequestBuilder.HTTPHeader {
        let all: [RequestBuilder.HTTPHeader] = [
            .contentTypeHeader(contentType: Bool.random() ? .applicationJSON : .textPlainUTF8),
            .userAgentHeader(appName: .mockRandom(among: .alphanumerics), appVersion: .mockRandom(among: .alphanumerics), device: .mockAny()),
            .ddAPIKeyHeader(clientToken: .mockRandom(among: .alphanumerics)),
            .ddEVPOriginHeader(source: .mockRandom(among: .alphanumerics)),
            .ddEVPOriginVersionHeader(sdkVersion: .mockRandom(among: .alphanumerics)),
            .ddRequestIDHeader()
        ]
        return all.randomElement()!
    }

    static func mockAny() -> RequestBuilder.HTTPHeader {
        return .ddEVPOriginVersionHeader(sdkVersion: "1.2.3")
    }
}

extension RequestBuilder: AnyMockable {
    static func mockAny() -> RequestBuilder {
        return mockWith()
    }

    static func mockWith(
        url: URL = .mockAny(),
        queryItems: [QueryItem] = [],
        headers: [HTTPHeader] = []
    ) -> RequestBuilder {
        return RequestBuilder(url: url, queryItems: queryItems, headers: headers)
    }
}

extension HTTPClient {
    static func mockAny() -> HTTPClient {
        return HTTPClient(session: URLSession())
    }
}

class NoOpDataUploadWorker: DataUploadWorkerType {
    func flushSynchronously() {}
    func cancelSynchronously() {}
}

struct DataUploaderMock: DataUploaderType {
    let uploadStatus: DataUploadStatus

    var onUpload: (() -> Void)? = nil

    func upload(data: Data) -> DataUploadStatus {
        onUpload?()
        return uploadStatus
    }
}

extension DataUploadStatus: RandomMockable {
    static func mockRandom() -> DataUploadStatus {
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

extension DeviceInfo {
    static func mockAny() -> DeviceInfo {
        return .mockWith()
    }

    static func mockWith(
        name: String = .mockAny(),
        model: String = .mockAny(),
        osName: String = .mockAny(),
        osVersion: String = .mockAny()
    ) -> DeviceInfo {
        return .init(
            name: name,
            model: model,
            osName: osName,
            osVersion: osVersion
        )
    }

    static func mockRandom() -> DeviceInfo {
        return .init(
            name: .mockRandom(),
            model: .mockRandom(),
            osName: .mockRandom(),
            osVersion: .mockRandom()
        )
    }
}

extension BatteryStatus.State {
    static func mockRandom(within cases: [BatteryStatus.State] = [.unknown, .unplugged, .charging, .full]) -> BatteryStatus.State {
        return cases.randomElement()!
    }
}

extension BatteryStatus {
    static func mockAny() -> BatteryStatus {
        return mockWith()
    }

    static func mockWith(
        state: State = .charging,
        level: Float = 0.5,
        isLowPowerModeEnabled: Bool = false
    ) -> BatteryStatus {
        return BatteryStatus(state: state, level: level, isLowPowerModeEnabled: isLowPowerModeEnabled)
    }
}

struct BatteryStatusProviderMock: BatteryStatusProviderType {
    let current: BatteryStatus

    static func mockWith(status: BatteryStatus ) -> BatteryStatusProviderMock {
        return BatteryStatusProviderMock(current: status)
    }

    static func mockAny() -> BatteryStatusProviderMock {
        return BatteryStatusProviderMock(current: .mockAny())
    }
}

extension NetworkConnectionInfo.Reachability {
    static func mockAny() -> NetworkConnectionInfo.Reachability {
        return .maybe
    }

    static func mockRandom(
        within cases: [NetworkConnectionInfo.Reachability] = [.yes, .no, .maybe]
    ) -> NetworkConnectionInfo.Reachability {
        return cases.randomElement()!
    }
}

extension NetworkConnectionInfo.Interface: RandomMockable {
    static func mockRandom() -> NetworkConnectionInfo.Interface {
        return allCases.randomElement()!
    }
}

extension NetworkConnectionInfo: RandomMockable {
    static func mockAny() -> NetworkConnectionInfo {
        return mockWith()
    }

    static func mockWith(
        reachability: NetworkConnectionInfo.Reachability = .mockAny(),
        availableInterfaces: [NetworkConnectionInfo.Interface] = [.wifi],
        supportsIPv4: Bool = true,
        supportsIPv6: Bool = true,
        isExpensive: Bool = true,
        isConstrained: Bool = true
    ) -> NetworkConnectionInfo {
        return NetworkConnectionInfo(
            reachability: reachability,
            availableInterfaces: availableInterfaces,
            supportsIPv4: supportsIPv4,
            supportsIPv6: supportsIPv6,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }

    static func mockRandom() -> NetworkConnectionInfo {
        return NetworkConnectionInfo(
            reachability: .mockRandom(),
            availableInterfaces: .mockRandom(),
            supportsIPv4: .random(),
            supportsIPv6: .random(),
            isExpensive: .random(),
            isConstrained: .random()
        )
    }
}

class NetworkConnectionInfoProviderMock: NetworkConnectionInfoProviderType, WrappedNetworkConnectionInfoProvider {
    private let queue = DispatchQueue(label: "com.datadoghq.NetworkConnectionInfoProviderMock")
    private var _current: NetworkConnectionInfo?

    init(networkConnectionInfo: NetworkConnectionInfo?) {
        _current = networkConnectionInfo
    }

    func set(current: NetworkConnectionInfo?) {
        queue.async { self._current = current }
    }

    // MARK: - NetworkConnectionInfoProviderType

    var current: NetworkConnectionInfo? {
        queue.sync { _current }
    }

    func subscribe<Observer: NetworkConnectionInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == NetworkConnectionInfo? {
    }

    // MARK: - Mocking

    static func mockAny() -> NetworkConnectionInfoProviderMock {
        return mockWith()
    }

    static func mockWith(
        networkConnectionInfo: NetworkConnectionInfo? = .mockAny()
    ) -> NetworkConnectionInfoProviderMock {
        return NetworkConnectionInfoProviderMock(networkConnectionInfo: networkConnectionInfo)
    }
}

extension CarrierInfo.RadioAccessTechnology: RandomMockable {
    static func mockAny() -> CarrierInfo.RadioAccessTechnology { .LTE }

    static func mockRandom() -> CarrierInfo.RadioAccessTechnology {
        return allCases.randomElement()!
    }
}

extension CarrierInfo: RandomMockable {
    static func mockAny() -> CarrierInfo {
        return mockWith()
    }

    static func mockWith(
        carrierName: String? = .mockAny(),
        carrierISOCountryCode: String? = .mockAny(),
        carrierAllowsVOIP: Bool = .mockAny(),
        radioAccessTechnology: CarrierInfo.RadioAccessTechnology = .mockAny()
    ) -> CarrierInfo {
        return CarrierInfo(
            carrierName: carrierName,
            carrierISOCountryCode: carrierISOCountryCode,
            carrierAllowsVOIP: carrierAllowsVOIP,
            radioAccessTechnology: radioAccessTechnology
        )
    }

    static func mockRandom() -> CarrierInfo {
        return CarrierInfo(
            carrierName: .mockRandom(),
            carrierISOCountryCode: .mockRandom(),
            carrierAllowsVOIP: .random(),
            radioAccessTechnology: .mockRandom()
        )
    }
}

class CarrierInfoProviderMock: CarrierInfoProviderType {
    private let queue = DispatchQueue(label: "com.datadoghq.CarrierInfoProviderMock")
    private var _current: CarrierInfo?

    init(carrierInfo: CarrierInfo?) {
        _current = carrierInfo
    }

    func set(current: CarrierInfo?) {
        queue.async { self._current = current }
    }

    // MARK: - CarrierInfoProviderType

    var current: CarrierInfo? {
        queue.sync { _current }
    }

    func subscribe<Observer: CarrierInfoObserver>(_ subscriber: Observer) where Observer.ObservedValue == CarrierInfo? {
    }

    // MARK: - Mocking

    static func mockAny() -> CarrierInfoProviderMock {
        return mockWith()
    }

    static func mockWith(
        carrierInfo: CarrierInfo = .mockAny()
    ) -> CarrierInfoProviderMock {
        return CarrierInfoProviderMock(carrierInfo: carrierInfo)
    }
}

extension CodableValue {
    static func mockAny() -> CodableValue {
        return CodableValue(String.mockAny())
    }
}

extension ValuePublisher: AnyMockable where Value: AnyMockable {
    static func mockAny() -> Self {
        return .init(initialValue: .mockAny())
    }
}

extension ValuePublisher: RandomMockable where Value: RandomMockable {
    static func mockRandom() -> Self {
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

extension DDError: RandomMockable {
    static func mockRandom() -> DDError {
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
    private(set) var recordedLogs: [(level: CoreLoggerLevel, message: String, error: Error?)] = []

    // MARK: - CoreLogger

    func log(_ level: CoreLoggerLevel, message: @autoclosure () -> String, error: Error?) {
        recordedLogs.append((level, message(), error))
    }

    func reset() {
        recordedLogs = []
    }

    // MARK: - Matching

    typealias RecordedLog = (message: String, error: DDError?)

    private func recordedLogs(ofLevel level: CoreLoggerLevel) -> [RecordedLog] {
        return recordedLogs
            .filter({ $0.level == level })
            .map { ($0.message, $0.error.map({ DDError(error: $0) })) }
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
    private(set) var description: String = "Telemetry logs:"

    func debug(id: String, message: String) {
        debugs.append(message)
        description.append("\n- [debug] \(message)")
    }

    func error(id: String, message: String, kind: String?, stack: String?) {
        errors.append((message: message, kind: kind, stack: stack))
        description.append("\n - [error] \(message), kind: \(kind ?? "nil"), stack: \(stack ?? "nil")")
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
