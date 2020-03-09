/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest
import DatadogTestHelpers
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
        defer { date.addTimeInterval(timeInterval) }
        return date
    }

    /// Pushes time forward by given number of seconds.
    func advance(bySeconds seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}

// MARK: - Files orchestration

extension WritableFileConditions {
    static func mockAny() -> WritableFileConditions {
        return WritableFileConditions(
            maxDirectorySize: 0,
            maxFileSize: 0,
            maxFileAgeForWrite: 0,
            maxNumberOfUsesOfFile: 0
        )
    }

    /// Write conditions causing `FilesOrchestrator` to always pick the same file for writting.
    static func mockWriteToSingleFile() -> WritableFileConditions {
        return WritableFileConditions(
            maxDirectorySize: .max,
            maxFileSize: .max,
            maxFileAgeForWrite: .greatestFiniteMagnitude,
            maxNumberOfUsesOfFile: .max
        )
    }

    /// Write conditions causing `FilesOrchestrator` to create new file for each write.
    static func mockWriteToNewFileEachTime() -> WritableFileConditions {
        return WritableFileConditions(
            maxDirectorySize: .max,
            maxFileSize: .max,
            maxFileAgeForWrite: .greatestFiniteMagnitude,
            maxNumberOfUsesOfFile: 1
        )
    }
}

extension ReadableFileConditions {
    static func mockAny() -> ReadableFileConditions {
        return ReadableFileConditions(minFileAgeForRead: 0, maxFileAgeForRead: 0)
    }

    /// Read conditions causing `FilesOrchestrator` to pick all files for reading, no matter of their creation time.
    static func mockReadAllFiles() -> ReadableFileConditions {
        return ReadableFileConditions(
            minFileAgeForRead: -1,
            maxFileAgeForRead: .greatestFiniteMagnitude
        )
    }
}

extension FilesOrchestrator {
    static func mockAny() -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: temporaryDirectory,
            writeConditions: .mockAny(),
            readConditions: .mockAny(),
            dateProvider: SystemDateProvider()
        )
    }

    /// Mocks `FilesOrchestrator` which always returns the same file for `getWritableFile()`.
    static func mockWriteToSingleFile(in directory: Directory) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: directory,
            writeConditions: .mockWriteToSingleFile(),
            readConditions: LogsPersistenceStrategy.defaultReadConditions,
            dateProvider: SystemDateProvider()
        )
    }

    /// Mocks `FilesOrchestrator` which does not perform age classification for `getReadableFile()`.
    static func mockReadAllFiles(in directory: Directory) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: directory,
            writeConditions: LogsPersistenceStrategy.defaultWriteConditions,
            readConditions: .mockReadAllFiles(),
            dateProvider: SystemDateProvider()
        )
    }
}

extension FileWriter {
    static func mockAny() -> FileWriter {
        return FileWriter(
            orchestrator: .mockAny(),
            queue: .global(),
            maxWriteSize: 0
        )
    }

    /// Mocks `FileWriter` writting data to single file with given name.
    static func mockWrittingToSingleFile(
        in directory: Directory,
        on queue: DispatchQueue
    ) -> FileWriter {
        return FileWriter(
            orchestrator: .mockWriteToSingleFile(in: directory),
            queue: queue,
            maxWriteSize: .max
        )
    }
}

extension FileReader {
    static func mockAny() -> FileReader {
        return FileReader(
            orchestrator: .mockAny(),
            queue: .global()
        )
    }
}

// MARK: - URLRequests delivery

typealias RequestsRecorder = URLSessionRequestRecorder

extension HTTPClient {
    static func mockAny() -> HTTPClient {
        return HTTPClient(session: .mockAny())
    }

    static func mockDeliverySuccessWith(responseStatusCode: Int, requestsRecorder: RequestsRecorder? = nil) -> HTTPClient {
        return HTTPClient(
            session: .mockDeliverySuccess(
                data: Data(),
                response: .mockResponseWith(statusCode: responseStatusCode),
                requestsRecorder: requestsRecorder
            )
        )
    }

    static func mockDeliveryFailureWith(error: Error, requestsRecorder: RequestsRecorder? = nil) -> HTTPClient {
        return HTTPClient(
            session: .mockDeliveryFailure(
                error: error,
                requestsRecorder: requestsRecorder
            )
        )
    }
}

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

    static func mockAny() -> BatteryStatusProviderMock {
        return BatteryStatusProviderMock(current: .mockAny())
    }

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
    let current: NetworkConnectionInfo

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

extension DataUploadURL {
    static func mockAny() -> DataUploadURL {
        return try! DataUploadURL(
            endpointURL: "https://app.example.com/v2/api",
            clientToken: "abc-def-ghi"
        )
    }
}

extension DataUploadDelay {
    static func mockAny() -> DataUploadDelay {
        return DataUploadDelay(default: 0, min: 0, max: 0, decreaseFactor: 0)
    }

    /// Mocks constant delay returning given amount of seconds, no matter of `.decrease()` or `.increaseOnce()` calls.
    static func mockConstantDelay(of seconds: TimeInterval) -> DataUploadDelay {
        return DataUploadDelay(
            default: seconds,
            min: seconds,
            max: seconds,
            decreaseFactor: 1
        )
    }
}

extension DataUploadConditions {
    static func mockAny() -> DataUploadConditions {
        return DataUploadConditions(
            batteryStatus: BatteryStatusProviderMock.mockAny(),
            networkConnectionInfo: NetworkConnectionInfoProviderMock.mockAny()
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
            url: .mockAny(),
            httpClient: .mockAny(),
            httpHeaders: .mockAny()
        )
    }
}

extension DataUploadWorker {
    static func mockAny() -> DataUploadWorker {
        return .mockWith()
    }

    static func mockWith(
        queue: DispatchQueue = .global(),
        fileReader: FileReader = .mockAny(),
        dataUploader: DataUploader = .mockAny(),
        uploadConditions: DataUploadConditions = .mockAny(),
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

extension LogsPersistenceStrategy {
    static func mockAny() -> LogsPersistenceStrategy {
        return LogsPersistenceStrategy(writer: .mockAny(), reader: .mockAny())
    }

    /// Mocks persistence strategy where:
    /// * new file is created for each write (so every log is written to new file);
    /// * file age is ignored when reading (so every file can be read immediately after writting);
    /// This strategy is valid, because `.default` strategy uses single thread to synchronize Writes and Reads.
    static func mockUseNewFileForEachWriteAndReadFilesIgnoringTheirAge(
        in directory: Directory,
        using dateProvider: DateProvider
    ) -> LogsPersistenceStrategy {
        return .default(
            in: directory,
            using: dateProvider,
            readWriteQueue: DispatchQueue(
                label: "com.datadoghq.ios-sdk-logs-read-write",
                target: .global(qos: .utility)
            ),
            writeConditions: .mockWriteToNewFileEachTime(),
            readConditions: .mockReadAllFiles()
        )
    }
}

extension LogsUploadStrategy {
    static func mockAny() -> LogsUploadStrategy {
        return LogsUploadStrategy(uploadWorker: .mockAny())
    }

    static func mockNeverPerformingUploads() -> LogsUploadStrategy {
        return LogsUploadStrategy(
            uploadWorker: .mockNeverPerformingUploads()
        )
    }

    /// Mocks upload strategy where:
    /// * batches are read with given `interval` of seconds using `fileReader`;
    /// * `URLRequest` passed to underlying `URLSession` are recorded on given `requestsRecorder`;
    /// * underlying `URLSession` mock responds with 200 OK status code.
    static func mockUploadBatchesInConstantDelayWith200ResponseStatusCode(
        interval: TimeInterval,
        using fileReader: FileReader,
        andRecordRequestsOn requestsRecorder: RequestsRecorder?,
        uploadConditions: DataUploadConditions
    ) -> LogsUploadStrategy {
        let uploadQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-tests-logs-upload",
            target: .global(qos: .utility)
        )
        return LogsUploadStrategy(
            uploadWorker: DataUploadWorker(
                queue: uploadQueue,
                fileReader: fileReader,
                dataUploader: DataUploader(
                    url: .mockAny(),
                    httpClient: .mockDeliverySuccessWith(
                        responseStatusCode: 200,
                        requestsRecorder: requestsRecorder
                    ),
                    httpHeaders: .mockAny()
                ),
                uploadConditions: uploadConditions,
                delay: .mockConstantDelay(of: interval)
            )
        )
    }
}

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
        bundleIdentifier: String? = nil,
        bundleVersion: String? = nil,
        bundleShortVersion: String? = nil,
        executableName: String? = nil,
        mobileDevice: MobileDevice? = nil
    ) -> AppContext {
        return AppContext(
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

extension Datadog.Configuration {
    static func mockAny() -> Datadog.Configuration {
        return mockWith()
    }

    static func mockWith(
        logsUploadURL: DataUploadURL? = .mockAny()
    ) -> Datadog.Configuration {
        return Datadog.Configuration(
            logsUploadURL: logsUploadURL
        )
    }
}

extension Datadog {
    static func mockNeverPerformingUploads() -> Datadog {
        return .mockWith(
            logsUploadStrategy: .mockNeverPerformingUploads()
        )
    }

    static func mockWith(
        appContext: AppContext = .mockAny(),
        logsPersistenceStrategy: LogsPersistenceStrategy = .mockAny(),
        logsUploadStrategy: LogsUploadStrategy = .mockAny(),
        dateProvider: DateProvider = SystemDateProvider(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderType? = CarrierInfoProviderMock.mockAny()
    ) -> Datadog {
        return Datadog(
            appContext: appContext,
            logsPersistenceStrategy: logsPersistenceStrategy,
            logsUploadStrategy: logsUploadStrategy,
            dateProvider: dateProvider,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}

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
class DatadogInstanceMock {
    private let requestsRecorder = RequestsRecorder()
    private let logsUploadInterval: TimeInterval = 0.05

    private var runClosure: (() -> Void)? = nil
    private var waitClosure: (() -> Void)? = nil
    private var waitExpectation: XCTestExpectation?

    static var builder: Builder { Builder() }

    class Builder {
        private var appContext: AppContext = .mockAny()
        private var dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
        private var networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockGoodConnection()
        private var carrierInfoProvider: CarrierInfoProviderType? = nil
        private var batteryStatusProvider: BatteryStatusProviderType = BatteryStatusProviderMock.mockFullBattery()

        func with(appContext: AppContext) -> Builder {
            self.appContext = appContext
            return self
        }

        func with(dateProvider: RelativeDateProvider) -> Builder {
            self.dateProvider = dateProvider
            return self
        }

        func with(networkConnectionInfoProvider: NetworkConnectionInfoProviderType) -> Builder {
            self.networkConnectionInfoProvider = networkConnectionInfoProvider
            return self
        }

        func with(carrierInfoProvider: CarrierInfoProviderType?) -> Builder {
            self.carrierInfoProvider = carrierInfoProvider
            return self
        }

        func with(batteryStatusProvider: BatteryStatusProviderType) -> Builder {
            self.batteryStatusProvider = batteryStatusProvider
            return self
        }

        func initialize() -> DatadogInstanceMock {
            return DatadogInstanceMock(
                appContext: appContext,
                dateProvider: dateProvider,
                networkConnectionInfoProvider: networkConnectionInfoProvider,
                carrierInfoProvider: carrierInfoProvider,
                batteryStatusProvider: batteryStatusProvider
            )
        }
    }

    private init(
        appContext: AppContext,
        dateProvider: RelativeDateProvider,
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
        carrierInfoProvider: CarrierInfoProviderType?,
        batteryStatusProvider: BatteryStatusProviderType
    ) {
        let logsPersistenceStrategy: LogsPersistenceStrategy = .mockUseNewFileForEachWriteAndReadFilesIgnoringTheirAge(
            in: temporaryDirectory,
            using: RelativeDateProvider(
                startingFrom: dateProvider.date,
                advancingBySeconds: dateProvider.timeInterval
            )
        )
        let logsUploadStrategy: LogsUploadStrategy = .mockUploadBatchesInConstantDelayWith200ResponseStatusCode(
            interval: logsUploadInterval,
            using: logsPersistenceStrategy.reader,
            andRecordRequestsOn: requestsRecorder,
            uploadConditions: DataUploadConditions(
                batteryStatus: batteryStatusProvider,
                networkConnectionInfo: networkConnectionInfoProvider
            )
        )

        // Instantiate `Datadog` object configured for sending one log per request.
        Datadog.instance = Datadog(
            appContext: appContext,
            logsPersistenceStrategy: logsPersistenceStrategy,
            logsUploadStrategy: logsUploadStrategy,
            dateProvider: dateProvider,
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }

    func run(closure: @escaping () -> Void) -> DatadogInstanceMock {
        runClosure = closure
        return self
    }

    func waitUntil(numberOfLogsSent: Int, file: StaticString = #file, line: UInt = #line) -> DatadogInstanceMock {
        // Configure asynchronous expectation to be fulfilled `numberOfLogsSent` times
        // as mocked `Datadog.instance` will be sending one log per request.
        let expectation = XCTestExpectation(description: "Send \(numberOfLogsSent) logs")
        expectation.expectedFulfillmentCount = numberOfLogsSent

        // Fulfill the expectation on every request sent.
        requestsRecorder.onNewRequest = { [expectation] _ in expectation.fulfill() }

        // Set the timeout to 8 times more than expected (arbitrary).
        let waitTime = logsUploadInterval * Double(numberOfLogsSent) * 8

        waitExpectation = expectation
        waitClosure = { [requestsRecorder] in
            let result = XCTWaiter().wait(for: [expectation], timeout: waitTime)

            switch result {
            case .completed:
                break
            case .incorrectOrder, .interrupted:
                fatalError("Can't happen.")
            case .timedOut:
                XCTFail(
                    "Exceeded timeout with sending only \(requestsRecorder.requestsSent.count) out of \(numberOfLogsSent) expected logs.",
                    file: file,
                    line: line
                )
            case .invertedFulfillment:
                XCTFail(
                    "\(requestsRecorder.requestsSent.count) requeste were sent, but not expected.",
                    file: file,
                    line: line
                )
            @unknown default:
                fatalError()
            }
        }
        return self
    }

    /// Use to verify all logs sent.
    func verifyAll(closure: @escaping ([LogMatcher]) throws -> Void) throws -> DatadogInstanceMock {
        precondition(runClosure != nil, "`.run {}` must preceed `.verify {}`")
        precondition(waitClosure != nil, "`.wait {}` must preceed `.verify {}`")

        runClosure?()
        waitClosure?()

        let logMatchers = try requestsRecorder.requestsSent
            .map { request in try request.httpBody.unwrapOrThrow() }
            .flatMap { requestBody in try requestBody.toArrayOfJSONObjects() }
            .map { jsonObject in LogMatcher(from: jsonObject) }

        try closure(logMatchers)

        return self
    }

    /// Use to verify the first log sent.
    func verifyFirst(closure: @escaping (LogMatcher) throws -> Void) throws -> DatadogInstanceMock {
        try verifyAll { allMatchers in
            try closure(allMatchers[0])
        }
    }

    func verifyNoLogsSent(file: StaticString = #file, line: UInt = #line) throws -> DatadogInstanceMock {
        precondition(runClosure != nil, "`.run {}` must preceed `.verify {}`")
        precondition(waitClosure != nil, "`.wait {}` must preceed `.verify {}`")

        waitExpectation?.isInverted = true

        runClosure?()
        waitClosure?()

        if requestsRecorder.requestsSent.count > 0 {
            XCTFail("\(requestsRecorder.requestsSent.count) requests were / was sent. ", file: file, line: line)
        }

        return self
    }

    func destroy() throws {
        try Datadog.deinitializeOrThrow()
    }
}
