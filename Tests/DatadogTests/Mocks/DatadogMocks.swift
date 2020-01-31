import Foundation
@testable import Datadog

/*
A collection of SDK object mocks.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

// MARK: - Date and time

/// Date provider which returns consecutive mocked dates in a loop.
class DateProviderMock: DateProvider {
    var currentDates: [Date]
    var currentFileCreationDates: [Date]

    private var index1 = 0
    private var index2 = 0

    init(currentDate: Date = Date(), currentFileCreationDate: Date = Date()) {
        self.currentDates = [currentDate]
        self.currentFileCreationDates = [currentFileCreationDate]
    }

    func currentDate() -> Date {
        defer { index1 = (index1 + 1) % currentDates.count }
        return currentDates[index1]
    }

    func currentFileCreationDate() -> Date {
        defer { index2 = (index2 + 1) % currentFileCreationDates.count }
        return currentFileCreationDates[index2]
    }

    /// Returns past date starting from `currentDate()`
    func secondsAgo(_ seconds: TimeInterval) -> Date {
        return currentDates[index1].secondsAgo(seconds)
    }

    /// Returns past date starting from `currentDate()`
    func minutesAgo(_ minutes: Double) -> Date {
        return currentDates[index1].minutesAgo(minutes)
    }

    /// Mocks `DateProvider` which always returns given date for `.currentDate()`
    static func mockReturning(currentDate: Date) -> DateProvider {
        let mock = DateProviderMock()
        mock.currentDates = [currentDate]
        return mock
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
    static func mockWriteToSingleFile(in directory: Directory, using dateProvider: DateProvider) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: directory,
            writeConditions: .mockWriteToSingleFile(),
            readConditions: LogsPersistenceStrategy.defaultReadConditions,
            dateProvider: dateProvider
        )
    }

    /// Mocks `FilesOrchestrator` which does not perform age classification for `getReadableFile()`.
    static func mockReadAllFiles(in directory: Directory, using dateProvider: DateProvider) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: directory,
            writeConditions: LogsPersistenceStrategy.defaultWriteConditions,
            readConditions: .mockReadAllFiles(),
            dateProvider: dateProvider
        )
    }
}

extension FileWriter {
    /// Mocks `FileWriter` writting data to single file with given name.
    static func mockWrittingToSingleFile(
        in directory: Directory,
        on queue: DispatchQueue,
        using dateProvider: DateProvider
    ) -> FileWriter {
        return FileWriter(
            orchestrator: .mockWriteToSingleFile(in: directory, using: dateProvider),
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
            logsFileCreationDateProvider: DateProviderMock(),
            logsUploadInterval: Date.distantFuture.timeIntervalSinceReferenceDate,
            logsTimeProvider: DateProviderMock(),
            requestsRecorder: nil
        )
    }
}
