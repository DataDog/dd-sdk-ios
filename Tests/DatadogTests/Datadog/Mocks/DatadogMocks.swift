/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest
@testable import Datadog

/*
A collection of SDK object mocks.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

// MARK: - Primitive types

extension String {
    /// Returns string being a valid name of the file managed by `FilesOrchestrator`.
    static func mockAnyFileName() -> String {
        return Date.mockAny().toFileName
    }
}

// MARK: - Date and time

/// `DateProvider` mock returning consecutive dates in custom intervals, starting from given reference date.
class RelativeDateProvider: DateProvider {
    private(set) var date: Date
    internal let timeInterval: TimeInterval
    private let queue = DispatchQueue(label: "queue-RelativeDateProvider-\(UUID().uuidString)")

    init(using date: Date = Date()) {
        self.date = date
        self.timeInterval = 0
    }

    init(startingFrom referenceDate: Date = Date(), advancingBySeconds timeInterval: TimeInterval = 0) {
        self.date = referenceDate
        self.timeInterval = timeInterval
    }

    /// Returns current date and advances next date by `timeInterval`.
    func currentDate() -> Date {
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

// MARK: - PerformancePreset

extension PerformancePreset {
    /// Mocks performance preset which results with no writes and no uploads.
    static func mockNoOp() -> PerformancePreset {
        return .mockWith(
            maxBatchSize: 0,
            maxSizeOfLogsDirectory: 0,
            maxFileAgeForWrite: 0,
            minFileAgeForRead: 0,
            maxFileAgeForRead: 0,
            maxLogsPerBatch: 0,
            maxLogSize: 0,
            initialLogsUploadDelay: 0,
            defaultLogsUploadDelay: 0,
            minLogsUploadDelay: 0,
            maxLogsUploadDelay: 0,
            logsUploadDelayDecreaseFactor: 1
        )
    }

    /// Mocks performance preset which optimizes read / write / upload time for fast unit tests execution.
    static func mockUnitTestsPerformancePreset() -> PerformancePreset {
        return PerformancePreset(
            // persistence
            maxBatchSize: .max, // unlimited
            maxSizeOfLogsDirectory: .max, // unlimited
            maxFileAgeForWrite: 0, // write each data to new file
            minFileAgeForRead: -1, // read all files
            maxFileAgeForRead: .distantFuture, // read all files
            maxLogsPerBatch: 1, // write each data to new file
            maxLogSize: .max, // unlimited

            // upload
            initialLogsUploadDelay: 0.05,
            defaultLogsUploadDelay: 0.05,
            minLogsUploadDelay: 0.05,
            maxLogsUploadDelay: 0.05,
            logsUploadDelayDecreaseFactor: 1
        )
    }

    /// Partial mock for performance preset optimized for different write / reads / upload use cases in unit tests.
    static func mockWith(
        maxBatchSize: UInt64 = .mockAny(),
        maxSizeOfLogsDirectory: UInt64 = .mockAny(),
        maxFileAgeForWrite: TimeInterval = .mockAny(),
        minFileAgeForRead: TimeInterval = .mockAny(),
        maxFileAgeForRead: TimeInterval = .mockAny(),
        maxLogsPerBatch: Int = .mockAny(),
        maxLogSize: UInt64 = .mockAny(),
        initialLogsUploadDelay: TimeInterval = .mockAny(),
        defaultLogsUploadDelay: TimeInterval = .mockAny(),
        minLogsUploadDelay: TimeInterval = .mockAny(),
        maxLogsUploadDelay: TimeInterval = .mockAny(),
        logsUploadDelayDecreaseFactor: Double = .mockAny()
    ) -> PerformancePreset {
        return PerformancePreset(
            maxBatchSize: maxBatchSize,
            maxSizeOfLogsDirectory: maxSizeOfLogsDirectory,
            maxFileAgeForWrite: maxFileAgeForWrite,
            minFileAgeForRead: minFileAgeForRead,
            maxFileAgeForRead: maxFileAgeForRead,
            maxLogsPerBatch: maxLogsPerBatch,
            maxLogSize: maxLogSize,
            initialLogsUploadDelay: initialLogsUploadDelay,
            defaultLogsUploadDelay: defaultLogsUploadDelay,
            minLogsUploadDelay: minLogsUploadDelay,
            maxLogsUploadDelay: maxLogsUploadDelay,
            logsUploadDelayDecreaseFactor: logsUploadDelayDecreaseFactor
        )
    }
}

// MARK: - Files orchestration

extension WritableFileConditions {
    /// Write conditions causing `FilesOrchestrator` to always pick the same file for writting.
    static func mockWriteToSingleFile() -> WritableFileConditions {
        return WritableFileConditions(
            performance: .mockWith(
                maxBatchSize: .max,
                maxSizeOfLogsDirectory: .max,
                maxFileAgeForWrite: .distantFuture,
                maxLogsPerBatch: .max,
                maxLogSize: .max
            )
        )
    }

    /// Write conditions causing `FilesOrchestrator` to create new file for each write.
    static func mockWriteToNewFileEachTime() -> WritableFileConditions {
        return WritableFileConditions(
            performance: .mockWith(
                maxBatchSize: .max,
                maxSizeOfLogsDirectory: .max,
                maxFileAgeForWrite: .distantFuture,
                maxLogsPerBatch: 1,
                maxLogSize: .max
            )
        )
    }
}

extension ReadableFileConditions {
    /// Read conditions causing `FilesOrchestrator` to pick all files for reading, no matter of their creation time.
    static func mockReadAllFiles() -> ReadableFileConditions {
        return ReadableFileConditions(
            performance: .mockWith(
                minFileAgeForRead: -1,
                maxFileAgeForRead: .distantFuture
            )
        )
    }
}

extension FilesOrchestrator {
    static func mockNoOp() -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: temporaryDirectory,
            writeConditions: WritableFileConditions(
                performance: .mockWith(
                    maxBatchSize: 0,
                    maxSizeOfLogsDirectory: 0,
                    maxFileAgeForWrite: .distantFuture,
                    maxLogsPerBatch: 0
                )
            ),
            readConditions: ReadableFileConditions(
                performance: .mockWith(
                    minFileAgeForRead: .distantFuture,
                    maxFileAgeForRead: .distantFuture
                )
            ),
            dateProvider: SystemDateProvider()
        )
    }

    /// Mocks `FilesOrchestrator` which always returns the same file for `getWritableFile()`.
    static func mockWriteToSingleFile(in directory: Directory) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: directory,
            writeConditions: .mockWriteToSingleFile(),
            readConditions: ReadableFileConditions(performance: .mockUnitTestsPerformancePreset()),
            dateProvider: SystemDateProvider()
        )
    }

    /// Mocks `FilesOrchestrator` which does not perform age classification for `getReadableFile()`.
    static func mockReadAllFiles(in directory: Directory) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: directory,
            writeConditions: WritableFileConditions(performance: .mockUnitTestsPerformancePreset()),
            readConditions: .mockReadAllFiles(),
            dateProvider: SystemDateProvider()
        )
    }
}

extension FileWriter {
    static func mockNoOp() -> FileWriter {
        return FileWriter(
            orchestrator: .mockNoOp(),
            queue: .global()
        )
    }

    /// Mocks `FileWriter` writting data to single file with given name.
    static func mockWrittingToSingleFile(
        in directory: Directory,
        on queue: DispatchQueue
    ) -> FileWriter {
        return FileWriter(
            orchestrator: .mockWriteToSingleFile(in: directory),
            queue: queue
        )
    }
}

extension FileReader {
    static func mockNoOp() -> FileReader {
        return FileReader(
            orchestrator: .mockNoOp(),
            queue: .global()
        )
    }
}

// MARK: - HTTP

extension HTTPHeaders {
    static func mockAny() -> HTTPHeaders {
        return HTTPHeaders(appContext: .mockAny())
    }
}

// MARK: - System

extension MobileDevice {
    static func mockAny() -> MobileDevice {
        return .mockWith()
    }

    static func mockWith(
        model: String = .mockAny(),
        osName: String = .mockAny(),
        osVersion: String = .mockAny(),
        enableBatteryStatusMonitoring: @escaping () -> Void = {},
        resetBatteryStatusMonitoring: @escaping () -> Void = {},
        currentBatteryStatus: @escaping () -> BatteryStatus = { .mockAny() }
    ) -> MobileDevice {
        return MobileDevice(
            model: model,
            osName: osName,
            osVersion: osVersion,
            enableBatteryStatusMonitoring: enableBatteryStatusMonitoring,
            resetBatteryStatusMonitoring: resetBatteryStatusMonitoring,
            currentBatteryStatus: currentBatteryStatus
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

    static func mockFullBattery() -> BatteryStatus {
        return mockWith(state: .full, level: 1, isLowPowerModeEnabled: false)
    }
}

struct BatteryStatusProviderMock: BatteryStatusProviderType {
    let current: BatteryStatus

    static func mockWith(status: BatteryStatus) -> BatteryStatusProviderMock {
        return BatteryStatusProviderMock(current: status)
    }

    static func mockFullBattery() -> BatteryStatusProviderMock {
        return BatteryStatusProviderMock(
            current: .mockFullBattery()
        )
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

extension NetworkConnectionInfo {
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
        return mockWith(
            reachability: NetworkConnectionInfo.Reachability.allCases.randomElement()!,
            availableInterfaces: [NetworkConnectionInfo.Interface.allCases.randomElement()!],
            supportsIPv4: .random(),
            supportsIPv6: .random(),
            isExpensive: .random(),
            isConstrained: .random()
        )
    }
}

class NetworkConnectionInfoProviderMock: NetworkConnectionInfoProviderType {
    var current: NetworkConnectionInfo

    init(networkConnectionInfo: NetworkConnectionInfo) {
        self.current = networkConnectionInfo
    }

    static func mockAny() -> NetworkConnectionInfoProviderMock {
        return mockWith()
    }

    static func mockWith(
        networkConnectionInfo: NetworkConnectionInfo = .mockAny()
    ) -> NetworkConnectionInfoProviderMock {
        return NetworkConnectionInfoProviderMock(networkConnectionInfo: networkConnectionInfo)
    }

    static func mockGoodConnection() -> NetworkConnectionInfoProviderMock {
        return .mockWith(
            networkConnectionInfo: .mockWith(
                reachability: .yes,
                availableInterfaces: [.wifi]
            )
        )
    }
}

extension CarrierInfo.RadioAccessTechnology {
    static func mockAny() -> CarrierInfo.RadioAccessTechnology { .LTE }
}

extension CarrierInfo {
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
        return mockWith(
            carrierName: .mockRandom(),
            carrierISOCountryCode: .mockRandom(),
            carrierAllowsVOIP: .random(),
            radioAccessTechnology: CarrierInfo.RadioAccessTechnology.allCases.randomElement()!
        )
    }
}

class CarrierInfoProviderMock: CarrierInfoProviderType {
    var current: CarrierInfo?

    init(carrierInfo: CarrierInfo?) {
        self.current = carrierInfo
    }

    static func mockAny() -> CarrierInfoProviderMock {
        return mockWith()
    }

    static func mockWith(
        carrierInfo: CarrierInfo = .mockAny()
    ) -> CarrierInfoProviderMock {
        return CarrierInfoProviderMock(carrierInfo: carrierInfo)
    }
}

// MARK: - Persistence and Upload

extension UploadURLProvider {
    static func mockAny() -> UploadURLProvider {
        return try! UploadURLProvider(
            endpointURL: "https://app.example.com/v2/api",
            clientToken: "abc-def-ghi",
            dateProvider: RelativeDateProvider(using: Date.mockDecember15th2019At10AMUTC())
        )
    }
}

extension DataUploadDelay {
    static func mockAny() -> DataUploadDelay {
        return DataUploadDelay(performance: .mockNoOp())
    }

    /// Mocks constant delay returning given amount of seconds, no matter of `.decrease()` or `.increaseOnce()` calls.
    static func mockConstantDelay(of seconds: TimeInterval) -> DataUploadDelay {
        return DataUploadDelay(
            performance: .mockWith(
                initialLogsUploadDelay: seconds,
                defaultLogsUploadDelay: seconds,
                minLogsUploadDelay: seconds,
                maxLogsUploadDelay: seconds,
                logsUploadDelayDecreaseFactor: 1
            )
        )
    }
}

extension DataUploadConditions {
    static func mockNeverPerformingUploads() -> DataUploadConditions {
        return DataUploadConditions(
            batteryStatus: BatteryStatusProviderMock(
                current: .mockWith(
                    state: .unplugged,
                    level: 0.01,
                    isLowPowerModeEnabled: true
                )
            ),
            networkConnectionInfo: NetworkConnectionInfoProviderMock.mockWith(
                networkConnectionInfo: .mockWith(
                    reachability: .no
                )
            )
        )
    }

    static func mockAlwaysPerformingUpload() -> DataUploadConditions {
        return DataUploadConditions(
            batteryStatus: BatteryStatusProviderMock.mockWith(
                status: BatteryStatus(state: .full, level: 100, isLowPowerModeEnabled: false)
            ),
            networkConnectionInfo: NetworkConnectionInfoProviderMock(
                networkConnectionInfo: NetworkConnectionInfo(
                    reachability: .yes,
                    availableInterfaces: [.wifi],
                    supportsIPv4: true,
                    supportsIPv6: true,
                    isExpensive: false,
                    isConstrained: false
                )
            )
        )
    }
}

extension DataUploader {
    static func mockAny() -> DataUploader {
        return DataUploader(
            urlProvider: .mockAny(),
            httpClient: .mockAny(),
            httpHeaders: .mockAny()
        )
    }
}

extension HTTPClient {
    static func mockAny() -> HTTPClient {
        return HTTPClient(session: URLSession())
    }
}

extension DataUploadWorker {
    static func mockNoOp() -> DataUploadWorker {
        return .mockWith()
    }

    static func mockWith(
        queue: DispatchQueue = .global(),
        fileReader: FileReader = .mockNoOp(),
        dataUploader: DataUploader = .mockAny(),
        uploadConditions: DataUploadConditions = .mockNeverPerformingUploads(),
        delay: DataUploadDelay = .mockAny()
    ) -> DataUploadWorker {
        return DataUploadWorker(
            queue: queue,
            fileReader: fileReader,
            dataUploader: dataUploader,
            uploadConditions: uploadConditions,
            delay: delay
        )
    }

    static func mockNeverPerformingUploads() -> DataUploadWorker {
        // This creates constant delay of distant future, so first upload will never start.
        // Big number is used instead of `.greatestFiniteMagnitude` as the latter might have
        // an undefined behaviour according to Apple docs.
        return .mockWith(
            delay: .mockConstantDelay(of: 1_000_000)
        )
    }
}

//extension LogsPersistenceStrategy {
//    static func mockNeverWrittingLogs() -> LogsPersistenceStrategy {
//        return LogsPersistenceStrategy(writer: .mockNoOp(), reader: .mockNoOp())
//    }
//
//    /// Mocks persistence strategy where:
//    /// * new file is created for each write (so every log is written to new file);
//    /// * file age is ignored when reading (so every file can be read immediately after writting);
//    /// This strategy is valid, because `.default` strategy uses single thread to synchronize Writes and Reads.
//    static func mockUseNewFileForEachWriteAndReadFilesIgnoringTheirAge(
//        in directory: Directory,
//        using dateProvider: DateProvider
//    ) -> LogsPersistenceStrategy {
//        let readWriteQueue = DispatchQueue(
//            label: "com.datadoghq.ios-sdk-logs-read-write",
//            target: .global(qos: .utility)
//        )
//        let orchestrator = FilesOrchestrator(
//            directory: directory,
//            writeConditions: .mockWriteToNewFileEachTime(),
//            readConditions: .mockReadAllFiles(),
//            dateProvider: dateProvider
//        )
//
//        return LogsPersistenceStrategy(
//            writer: FileWriter(orchestrator: orchestrator, queue: readWriteQueue, maxWriteSize: .max),
//            reader: FileReader(orchestrator: orchestrator, queue: readWriteQueue)
//        )
//    }
//}

//extension LogsUploadStrategy {
//    static func mockNeverPerformingUploads() -> LogsUploadStrategy {
//        return LogsUploadStrategy(
//            uploadWorker: .mockNeverPerformingUploads()
//        )
//    }
//
//    /// Mocks upload strategy where:
//    /// * batches are read with given `interval` of seconds using `fileReader`;
//    static func mockUploadBatchesInConstantDelay(
//        interval: TimeInterval,
//        using fileReader: FileReader,
//        uploadConditions: DataUploadConditions,
//        urlSession: URLSession
//    ) -> LogsUploadStrategy {
//        let uploadQueue = DispatchQueue(
//            label: "com.datadoghq.ios-sdk-tests-logs-upload",
//            target: .global(qos: .utility)
//        )
//        return LogsUploadStrategy(
//            uploadWorker: DataUploadWorker(
//                queue: uploadQueue,
//                fileReader: fileReader,
//                dataUploader: DataUploader(
//                    urlProvider: .mockAny(),
//                    httpClient: HTTPClient(session: urlSession),
//                    httpHeaders: .mockAny()
//                ),
//                uploadConditions: uploadConditions,
//                delay: .mockConstantDelay(of: interval)
//            )
//        )
//    }
//}

// MARK: - Integration

/// Mock which can be used to intercept messages printed by `developerLogger` or
/// `userLogger` by overwritting `Datadog.consolePrint` function:
///
///     let printFunction = PrintFunctionMock()
///     consolePrint = printFunction.print
///
class PrintFunctionMock {
    private(set) var printedMessage: String?

    func print(message: String) {
        printedMessage = message
    }
}

extension AppContext {
    static func mockAny() -> AppContext {
        return mockWith()
    }

    static func mockWith(
        environment: Environment = .iOSApp,
        bundleIdentifier: String? = nil,
        bundleVersion: String? = nil,
        bundleShortVersion: String? = nil,
        executableName: String? = nil,
        mobileDevice: MobileDevice? = nil
    ) -> AppContext {
        return AppContext(
            environment: environment,
            bundleIdentifier: bundleIdentifier,
            bundleVersion: bundleVersion,
            bundleShortVersion: bundleShortVersion,
            executableName: executableName,
            mobileDevice: mobileDevice
        )
    }
}

extension UserInfo {
    static func mockAny() -> UserInfo {
        return mockEmpty()
    }

    static func mockEmpty() -> UserInfo {
        return UserInfo(id: nil, name: nil, email: nil)
    }

    static func mockRandom() -> UserInfo {
        return UserInfo(
            id: .mockRandom(),
            name: .mockRandom(),
            email: .mockRandom()
        )
    }
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

/// `LogOutput` recording received logs.
class LogOutputMock: LogOutput {
    struct RecordedLog: Equatable {
        let level: LogLevel
        let message: String
    }

    var recordedLog: RecordedLog? = nil

    func writeLogWith(level: LogLevel, message: String, attributes: [String: Encodable], tags: Set<String>) {
        recordedLog = RecordedLog(level: level, message: message)
    }
}

extension Datadog {
    /// Mocks no-op `Datadog` instance.
//    static func mockNoOp() -> Datadog {
//        return Datadog(
//            userInfoProvider: UserInfoProvider()
//        )
//    }
}
//
//    static func mockNoOpWith(
//        appContext: AppContext = .mockAny(),
//        logsPersistenceStrategy: LogsPersistenceStrategy = .mockNeverWrittingLogs(),
//        logsUploadStrategy: LogsUploadStrategy = .mockNeverPerformingUploads(),
//        dateProvider: DateProvider = SystemDateProvider(),
//        userInfoProvider: UserInfoProvider = .mockAny(),
//        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
//        carrierInfoProvider: CarrierInfoProviderType? = CarrierInfoProviderMock.mockAny()
//    ) -> Datadog {
//        return Datadog(
//            appContext: appContext,
//            logsPersistenceStrategy: logsPersistenceStrategy,
//            logsUploadStrategy: logsUploadStrategy,
//            dateProvider: dateProvider,
//            userInfoProvider: userInfoProvider,
//            networkConnectionInfoProvider: networkConnectionInfoProvider,
//            carrierInfoProvider: carrierInfoProvider
//        )
//    }
//}

/// Wraps and mocks `Datadog.initialize(...)` to configure SDK in tests.
/// All underlying componetns are instantiated and properly mocked.
/// Requests passed to `URLSession` are captured and their data is passed to `verifyAll {}` method as `[LogMatcher]`.
///
/// Example usage:
///
///     try DatadogInstanceMock.build
///         .with(appContext:)
///         .with(dateProvider:)
///         ...
///         .initialize()
///         .run {
///             let logger = Logger.builder.build()
///             logger.debug(...) // send logs
///         }
///         .waitUntil(numberOfLogsSent: 3) // expect number of logs
///         .verifyAll { logMatchers in
///             logMatchers[0].assert ... // verify logs
///             logMatchers[1].assert ...
///             logMatchers[2].assert ...
///         }
///         .destroy()
///
//class DatadogInstanceMock {
//    static let dataUploadInterval: TimeInterval = 0.05
//
//    private let server: ServerMock
//    private var runClosure: (() -> Void)? = nil
//    private var waitClosure: (() -> Void)? = nil
//    private var recordedRequests: [URLRequest] = []
//
//    static var builder: Builder { Builder() }
//
//    class Builder {
//        private var appContext: AppContext = .mockAny()
//        private var dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
//        private var networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockGoodConnection()
//        private var carrierInfoProvider: CarrierInfoProviderType? = nil
//        private var batteryStatusProvider: BatteryStatusProviderType = BatteryStatusProviderMock.mockFullBattery()
//
//        func with(appContext: AppContext) -> Builder {
//            self.appContext = appContext
//            return self
//        }
//
//        func with(dateProvider: RelativeDateProvider) -> Builder {
//            self.dateProvider = dateProvider
//            return self
//        }
//
//        func with(networkConnectionInfoProvider: NetworkConnectionInfoProviderType) -> Builder {
//            self.networkConnectionInfoProvider = networkConnectionInfoProvider
//            return self
//        }
//
//        func with(carrierInfoProvider: CarrierInfoProviderType?) -> Builder {
//            self.carrierInfoProvider = carrierInfoProvider
//            return self
//        }
//
//        func with(batteryStatusProvider: BatteryStatusProviderType) -> Builder {
//            self.batteryStatusProvider = batteryStatusProvider
//            return self
//        }
//
//        func initialize() -> DatadogInstanceMock {
//            return DatadogInstanceMock(
//                appContext: appContext,
//                dateProvider: dateProvider,
//                networkConnectionInfoProvider: networkConnectionInfoProvider,
//                carrierInfoProvider: carrierInfoProvider,
//                batteryStatusProvider: batteryStatusProvider
//            )
//        }
//    }
//
//    private init(
//        appContext: AppContext,
//        dateProvider: RelativeDateProvider,
//        networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
//        carrierInfoProvider: CarrierInfoProviderType?,
//        batteryStatusProvider: BatteryStatusProviderType
//    ) {
//        self.server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
//        let logsPersistenceStrategy: LogsPersistenceStrategy = .mockUseNewFileForEachWriteAndReadFilesIgnoringTheirAge(
//            in: temporaryDirectory,
//            using: RelativeDateProvider(
//                startingFrom: dateProvider.date,
//                advancingBySeconds: dateProvider.timeInterval
//            )
//        )
//        let logsUploadStrategy: LogsUploadStrategy = .mockUploadBatchesInConstantDelay(
//            interval: DatadogInstanceMock.dataUploadInterval,
//            using: logsPersistenceStrategy.reader,
//            uploadConditions: DataUploadConditions(
//                batteryStatus: batteryStatusProvider,
//                networkConnectionInfo: networkConnectionInfoProvider
//            ),
//            urlSession: server.urlSession
//        )
//
//        // Instantiate `Datadog` object configured for sending one log per request.
//        Datadog.instance = Datadog(
//            appContext: appContext,
//            logsPersistenceStrategy: logsPersistenceStrategy,
//            logsUploadStrategy: logsUploadStrategy,
//            dateProvider: dateProvider,
//            userInfoProvider: .mockAny(),
//            networkConnectionInfoProvider: networkConnectionInfoProvider,
//            carrierInfoProvider: carrierInfoProvider
//        )
//    }
//
//    func run(closure: @escaping () -> Void) -> DatadogInstanceMock {
//        runClosure = closure
//        return self
//    }
//
//    func waitUntil(numberOfLogsSent: Int, file: StaticString = #file, line: UInt = #line) -> DatadogInstanceMock {
//        // Set the timeout to 40 times more than expected.
//        // In `RUMM-311` we observed 0.66% of flakiness for 150 test runs on CI with arbitrary value of `20`.
//        let timeout = DatadogInstanceMock.dataUploadInterval * Double(numberOfLogsSent) * 40
//
//        waitClosure = { [weak self] in
//            guard let self = self else {
//                return
//            }
//            self.recordedRequests = self.server.waitAndReturnRequests(count: numberOfLogsSent, timeout: timeout)
//        }
//
//        return self
//    }
//
//    /// Use to verify all logs sent.
//    func verifyAll(closure: @escaping ([LogMatcher]) throws -> Void) throws -> DatadogInstanceMock {
//        precondition(runClosure != nil, "`.run {}` must preceed `.verify {}`")
//        precondition(waitClosure != nil, "`.wait {}` must preceed `.verify {}`")
//
//        runClosure?()
//        waitClosure?()
//
//        let logMatchers = try recordedRequests
//            .map { request in try request.httpBody.unwrapOrThrow() }
//            .flatMap { requestBody in try LogMatcher.fromArrayOfJSONObjectsData(requestBody) }
//
//        try closure(logMatchers)
//
//        return self
//    }
//
//    /// Use to verify the first log sent.
//    func verifyFirst(closure: @escaping (LogMatcher) throws -> Void) throws -> DatadogInstanceMock {
//        try verifyAll { allMatchers in
//            try closure(allMatchers[0])
//        }
//    }
//
//    func verifyNoLogsSent(within time: TimeInterval, file: StaticString = #file, line: UInt = #line) throws -> DatadogInstanceMock {
//        precondition(runClosure != nil, "`.run {}` must preceed `.verify {}`")
//        precondition(waitClosure == nil, "`.wait {}` cannot be used with `.verifyNoLogsSent {}`")
//
//        runClosure?()
//
//        let requests = server.waitAndReturnRequests(count: 0, timeout: time)
//        XCTAssertEqual(requests.count, 0, file: file, line: line)
//
//        return self
//    }
//
//    /// Verifies given block without running `run()` and `wait()`.
//    func verifyBlock(closure: @escaping () throws -> Void) throws -> DatadogInstanceMock {
//        try closure()
//        return self
//    }
//
//    func destroy() throws {
//        try Datadog.deinitializeOrThrow()
//    }
//}
