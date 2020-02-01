import Foundation
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
    private var date: Date
    private let timeInterval: TimeInterval

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

    /// Returns current date and advances next date by `timeInterval`.
    func currentFileCreationDate() -> Date {
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
    /// Read conditions causing `FilesOrchestrator` to pick all files for reading, no matter of their creation time.
    static func mockReadAllFiles() -> ReadableFileConditions {
        return ReadableFileConditions(
            minFileAgeForRead: -1,
            maxFileAgeForRead: .greatestFiniteMagnitude
        )
    }
}

extension FilesOrchestrator {
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

// MARK: - URLRequests delivery

typealias RequestsRecorder = URLSessionRequestRecorder

extension HTTPClient {
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

extension LogsPersistenceStrategy {
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
    /// Mocks upload strategy where:
    /// * batches are read with given `interval` of seconds using `fileReader`;
    /// * `URLRequest` passed to underlying `URLSession` are recorded on given `requestsRecorder`;
    /// * underlying `URLSession` mock responds with 200 OK status code.
    static func mockUploadBatchesInConstantDelayWith200ResponseStatusCode(
        interval: TimeInterval,
        using fileReader: FileReader,
        andRecordRequestsOn requestsRecorder: RequestsRecorder?
    ) -> LogsUploadStrategy {
        return .defalut(
            dataUploader: DataUploader(
                url: .mockAny(),
                httpClient: .mockDeliverySuccessWith(
                    responseStatusCode: 200,
                    requestsRecorder: requestsRecorder
                )
            ),
            reader: fileReader,
            uploadDelay: .mockConstantDelay(of: interval)
        )
    }
}

// MARK: - Integration

extension Datadog {
    /// Mocks SDK instance successfully delivering logs (with 200OK HTTP response returned from underlying `URLSession` mock).
    /// - Parameters:
    ///   - logsDirectory: directory where log files are created.
    ///   - logsFileCreationDateProvider: date provider used by `FilesOrchestrator` to create and access log files.
    ///   - logsUploadInterval: constant time interval used to uploads logs.
    ///   - logsTimeProvider: date provider used by `LogsWritter` to set `date` in `Log`.
    ///   - requestsRecorder: requests recorder recording all requests passed to `URLSession`.
    static func mockSuccessfullySendingOneLogPerRequest(
        logsDirectory: Directory,
        logsFileCreationDateProvider: DateProvider,
        logsUploadInterval: TimeInterval,
        logsTimeProvider: DateProvider,
        requestsRecorder: RequestsRecorder?
    ) -> Datadog {
        let logsPersistenceStrategy: LogsPersistenceStrategy = .mockUseNewFileForEachWriteAndReadFilesIgnoringTheirAge(
            in: temporaryDirectory,
            using: logsFileCreationDateProvider
        )
        let logsUploadStrategy: LogsUploadStrategy = .mockUploadBatchesInConstantDelayWith200ResponseStatusCode(
            interval: logsUploadInterval,
            using: logsPersistenceStrategy.reader,
            andRecordRequestsOn: requestsRecorder
        )
        return Datadog(
            logsPersistenceStrategy: logsPersistenceStrategy,
            logsUploadStrategy: logsUploadStrategy,
            dateProvider: logsTimeProvider
        )
    }

    /// Mocks SDK instance which doesn't send logs.
    static func mockAny(logsDirectory: Directory) -> Datadog {
        return .mockSuccessfullySendingOneLogPerRequest(
            logsDirectory: logsDirectory,
            logsFileCreationDateProvider: RelativeDateProvider(),
            logsUploadInterval: Date.distantFuture.timeIntervalSinceReferenceDate,
            logsTimeProvider: RelativeDateProvider(),
            requestsRecorder: nil
        )
    }
}
