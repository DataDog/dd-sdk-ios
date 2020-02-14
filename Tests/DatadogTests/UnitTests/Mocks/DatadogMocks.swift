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
        return BatteryStatus(state: .charging, level: 50, isLowPowerModeEnabled: false)
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
        return NetworkConnectionInfo(
            reachability: .yes,
            availableInterfaces: [],
            supportsIPv4: false,
            supportsIPv6: false,
            isExpensive: false,
            isConstrained: false
        )
    }
}

struct NetworkConnectionInfoProviderMock: NetworkConnectionInfoProviderType {
    let current: NetworkConnectionInfo

    static func mockAny() -> NetworkConnectionInfoProviderMock {
        return NetworkConnectionInfoProviderMock(
            current: .mockAny()
        )
    }

    static func mockWith(
        reachability: NetworkConnectionInfo.Reachability = .mockAny(),
        availableInterfaces: [NetworkConnectionInfo.Interface] = [.wifi],
        supportsIPv4: Bool = true,
        supportsIPv6: Bool = true,
        isExpensive: Bool = true,
        isConstrained: Bool = true
    ) -> NetworkConnectionInfoProviderMock {
        return NetworkConnectionInfoProviderMock(
            current: NetworkConnectionInfo(
                reachability: reachability,
                availableInterfaces: availableInterfaces,
                supportsIPv4: supportsIPv4,
                supportsIPv6: supportsIPv6,
                isExpensive: isExpensive,
                isConstrained: isConstrained
            )
        )
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
                current: NetworkConnectionInfo(
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
        return DataUploadWorker(
            queue: .global(),
            fileReader: .mockAny(),
            dataUploader: .mockAny(),
            uploadConditions: .mockAny(),
            delay: .mockAny()
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
            writeConditions: .mockWriteToNewFileEachTime(),
            readConditions: .mockReadAllFiles()
        )
    }
}

extension LogsUploadStrategy {
    static func mockAny() -> LogsUploadStrategy {
        return LogsUploadStrategy(uploadWorker: .mockAny())
    }

    /// Mocks upload strategy where:
    /// * batches are read with given `interval` of seconds using `fileReader`;
    /// * `URLRequest` passed to underlying `URLSession` are recorded on given `requestsRecorder`;
    /// * underlying `URLSession` mock responds with 200 OK status code.
    static func mockUploadBatchesInConstantDelayWith200ResponseStatusCode(
        interval: TimeInterval,
        using fileReader: FileReader,
        andRecordRequestsOn requestsRecorder: RequestsRecorder?
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
                uploadConditions: .mockAlwaysPerformingUpload(),
                delay: .mockConstantDelay(of: interval)
            )
        )
    }
}

// MARK: - Integration

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
        return UserInfoProvider()
    }

    static func mockWith(userInfo: UserInfo) -> UserInfoProvider {
        let provider = UserInfoProvider()
        provider.value = userInfo
        return provider
    }
}

extension Datadog {
    static func mockAny() -> Datadog {
        return mockWith()
    }

    static func mockWith(
        appContext: AppContext = .mockAny(),
        logsPersistenceStrategy: LogsPersistenceStrategy = .mockAny(),
        logsUploadStrategy: LogsUploadStrategy = .mockAny(),
        dateProvider: DateProvider = SystemDateProvider(),
        userInfoProvider: UserInfoProvider = .mockAny()
    ) -> Datadog {
        return Datadog(
            appContext: appContext,
            logsPersistenceStrategy: logsPersistenceStrategy,
            logsUploadStrategy: logsUploadStrategy,
            dateProvider: dateProvider,
            userInfoProvider: userInfoProvider
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

    static var build: Builder { Builder() }

    class Builder {
        private var appContext: AppContext = .mockAny()
        private var userInfoProvider: UserInfoProvider = .mockAny()
        private var dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)

        func with(appContext: AppContext) -> Builder {
            self.appContext = appContext
            return self
        }

        func with(userInfoProvider: UserInfoProvider) -> Builder {
            self.userInfoProvider = userInfoProvider
            return self
        }

        func with(dateProvider: RelativeDateProvider) -> Builder {
            self.dateProvider = dateProvider
            return self
        }

        func initialize() -> DatadogInstanceMock {
            return DatadogInstanceMock(
                appContext: appContext,
                userInfoProvider: userInfoProvider,
                dateProvider: dateProvider
            )
        }
    }

    private init(
        appContext: AppContext,
        userInfoProvider: UserInfoProvider,
        dateProvider: RelativeDateProvider
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
            andRecordRequestsOn: requestsRecorder
        )

        // Instantiate `Datadog` object configured for sending one log per request.
        Datadog.instance = Datadog(
            appContext: appContext,
            logsPersistenceStrategy: logsPersistenceStrategy,
            logsUploadStrategy: logsUploadStrategy,
            dateProvider: dateProvider,
            userInfoProvider: userInfoProvider
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

        waitClosure = { [requestsRecorder] in
            let result = XCTWaiter().wait(for: [expectation], timeout: waitTime)

            switch result {
            case .completed:
                break
            case .incorrectOrder, .interrupted, .invertedFulfillment:
                fatalError("Can't happen.")
            case .timedOut:
                XCTFail(
                    "Exceeded time out with sending only \(requestsRecorder.requestsSent.count) out of \(numberOfLogsSent) expected logs.",
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

    func destroy() throws {
        try Datadog.deinitializeOrThrow()
    }
}
