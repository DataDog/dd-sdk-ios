import Foundation
@testable import Datadog

/*
A collection of mock configurations for SDK.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension LogsUploader {
    /// Mocks `LogsUploader` instance which notifies sent requests on `captureBlock`.
    static func mockUploaderCapturingRequests(captureBlock: @escaping (URLRequest) -> Void) -> LogsUploader {
        return LogsUploader(
            validURL: .mockAny(),
            httpClient: .mockRequestCapture(captureBlock: captureBlock)
        )
    }
}

/// Date provider which returns consecutive mocked dates in a loop.
class DateProviderMock: DateProvider {
    var currentDates = [Date()]
    var currentFileCreationDates = [Date()]

    private var index1 = 0
    private var index2 = 0

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
}

extension WritableFileConditions {
    /// Write conditions for a file that can accept infinite number of data.
    static func mockUseSingleFile() -> WritableFileConditions {
        return WritableFileConditions(
            maxFileSize: .max,
            maxFileAgeForWrite: .greatestFiniteMagnitude,
            maxNumberOfUsesOfFile: .max
        )
    }
}

extension ReadableFileConditions {
    /// Read conditions for accepting all past files for read.
    static func mockReadAllFiles() -> ReadableFileConditions {
        return ReadableFileConditions(
            minFileAgeForRead: -1
        )
    }
}

extension FilesOrchestrator {
    /// Mocks `FilesOrchestrator` which always returns the same file for `getWritableFile()`.
    static func mockWriteToSingleFile(in directory: Directory) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: directory,
            writeConditions: .mockUseSingleFile(),
            readConditions: .default,
            dateProvider: SystemDateProvider()
        )
    }

    /// Mocks `FilesOrchestrator` which does not perform age classification for `getReadableFile()`.
    static func mockReadAllFiles(in directory: Directory) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: directory,
            writeConditions: .default,
            readConditions: .mockReadAllFiles(),
            dateProvider: SystemDateProvider()
        )
    }
}
