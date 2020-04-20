/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct WritableFileConditions {
    let maxDirectorySize: UInt64
    let maxFileSize: UInt64
    let maxFileAgeForWrite: TimeInterval
    let maxNumberOfUsesOfFile: Int
    let maxWriteSize: UInt64

    init(performance: PerformancePreset) {
        self.maxDirectorySize = performance.maxSizeOfLogsDirectory
        self.maxFileSize = performance.maxBatchSize
        self.maxFileAgeForWrite = performance.maxFileAgeForWrite
        self.maxNumberOfUsesOfFile = performance.maxLogsPerBatch
        self.maxWriteSize = performance.maxLogSize
    }
}

internal struct ReadableFileConditions {
    let minFileAgeForRead: TimeInterval
    let maxFileAgeForRead: TimeInterval

    init(performance: PerformancePreset) {
        minFileAgeForRead = performance.minFileAgeForRead
        maxFileAgeForRead = performance.maxFileAgeForRead
    }
}

internal class FilesOrchestrator {
    /// Directory where files are stored.
    private let directory: Directory
    /// Date provider.
    private let dateProvider: DateProvider
    /// Conditions for picking up writable file.
    private let writeConditions: WritableFileConditions
    /// Conditions for picking up readable file.
    private let readConditions: ReadableFileConditions
    /// Name of the last file returned by `getWritableFile()`.
    private var lastWritableFileName: String? = nil
    /// Tracks number of times the file at `lastWritableFileURL` was returned from `getWritableFile()`.
    private var lastWritableFileUsesCount: Int = 0

    init(
        directory: Directory,
        writeConditions: WritableFileConditions,
        readConditions: ReadableFileConditions,
        dateProvider: DateProvider
    ) {
        self.directory = directory
        self.writeConditions = writeConditions
        self.readConditions = readConditions
        self.dateProvider = dateProvider
    }

    // MARK: - `WritableFile` orchestration

    func getWritableFile(writeSize: UInt64) throws -> WritableFile {
        if writeSize > writeConditions.maxWriteSize {
            throw InternalError(description: "data exceeds the maximum size of \(writeConditions.maxWriteSize) bytes.")
        }

        try purgeFilesDirectoryIfNeeded()

        let lastWritableFileOrNil = reuseLastWritableFileIfPossible(writeSize: writeSize)

        if let lastWritableFile = lastWritableFileOrNil { // if last writable file can be reused
            lastWritableFileUsesCount += 1
            return lastWritableFile
        } else {
            let newFileName = fileNameFrom(fileCreationDate: dateProvider.currentDate())
            let newFile = try directory.createFile(named: newFileName)
            lastWritableFileName = newFile.name
            lastWritableFileUsesCount = 1
            return newFile
        }
    }

    private func reuseLastWritableFileIfPossible(writeSize: UInt64) -> WritableFile? {
        if let lastFileName = lastWritableFileName {
            do {
                let lastFile = try directory.file(named: lastFileName)
                let lastFileCreationDate = fileCreationDateFrom(fileName: lastFile.name)
                let lastFileAge = dateProvider.currentDate().timeIntervalSince(lastFileCreationDate)

                let fileIsRecentEnough = lastFileAge <= writeConditions.maxFileAgeForWrite
                let fileHasRoomForMore = (try lastFile.size() + writeSize) <= writeConditions.maxFileSize
                let fileCanBeUsedMoreTimes = (lastWritableFileUsesCount + 1) <= writeConditions.maxNumberOfUsesOfFile

                if fileIsRecentEnough && fileHasRoomForMore && fileCanBeUsedMoreTimes {
                    return lastFile
                }
            } catch {
                developerLogger?.error("🔥 Failed to read previously used writable file: \(error)")
            }
        }

        return nil
    }

    // MARK: - `ReadableFile` orchestration

    func getReadableFile(excludingFilesNamed excludedFileNames: Set<String> = []) -> ReadableFile? {
        do {
            let filesWithCreationDate = try directory.files()
                .map { (file: $0, creationDate: fileCreationDateFrom(fileName: $0.name)) }
                .compactMap { try deleteFileIfItsObsolete(file: $0.file, fileCreationDate: $0.creationDate) }

            guard let (oldestFile, creationDate) = filesWithCreationDate
                .filter({ excludedFileNames.contains($0.file.name) == false })
                .sorted(by: { $0.creationDate < $1.creationDate })
                .first
            else {
                return nil
            }

            let oldestFileAge = dateProvider.currentDate().timeIntervalSince(creationDate)
            let fileIsOldEnough = oldestFileAge >= readConditions.minFileAgeForRead

            return fileIsOldEnough ? oldestFile : nil
        } catch {
            developerLogger?.error("🔥 Failed to obtain readable file: \(error)")
            return nil
        }
    }

    func delete(readableFile: ReadableFile) {
        do {
            try readableFile.delete()
        } catch {
            developerLogger?.error("🔥 Failed to delete file: \(error)")
        }
    }

    // MARK: - Directory size management

    /// Removes oldest files from the directory if it becomes too big.
    private func purgeFilesDirectoryIfNeeded() throws {
        let filesSortedByCreationDate = try directory.files()
            .map { (file: $0, creationDate: fileCreationDateFrom(fileName: $0.name)) }
            .sorted { $0.creationDate < $1.creationDate }

        var filesWithSizeSortedByCreationDate = try filesSortedByCreationDate
            .map { (file: $0.file, size: try $0.file.size()) }

        let accumulatedFilesSize = filesWithSizeSortedByCreationDate.map { $0.size }.reduce(0, +)

        if accumulatedFilesSize > writeConditions.maxDirectorySize {
            let sizeToFree = accumulatedFilesSize - writeConditions.maxDirectorySize
            var sizeFreed: UInt64 = 0

            while sizeFreed < sizeToFree && !filesWithSizeSortedByCreationDate.isEmpty {
                let fileWithSize = filesWithSizeSortedByCreationDate.removeFirst()
                try fileWithSize.file.delete()
                sizeFreed += fileWithSize.size
            }
        }
    }

    private func deleteFileIfItsObsolete(file: File, fileCreationDate: Date) throws -> (file: File, creationDate: Date)? {
        let fileAge = dateProvider.currentDate().timeIntervalSince(fileCreationDate)

        if fileAge > readConditions.maxFileAgeForRead {
            try file.delete()
            return nil
        } else {
            return (file: file, creationDate: fileCreationDate)
        }
    }
}

/// File creation date is used as file name - timestamp in milliseconds is used for date representation.
/// This function converts file creation date into file name.
internal func fileNameFrom(fileCreationDate: Date) -> String {
    let milliseconds = fileCreationDate.timeIntervalSinceReferenceDate * 1_000
    let converted = (try? UInt64(withReportingOverflow: milliseconds)) ?? 0
    return String(converted)
}

/// File creation date is used as file name - timestamp in milliseconds is used for date representation.
/// This function converts file name into file creation date.
internal func fileCreationDateFrom(fileName: String) -> Date {
    let millisecondsSinceReferenceDate = TimeInterval(UInt64(fileName) ?? 0) / 1_000
    return Date(timeIntervalSinceReferenceDate: TimeInterval(millisecondsSinceReferenceDate))
}
