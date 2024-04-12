/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol FilesOrchestratorType: AnyObject {
    var performance: StoragePerformancePreset { get }

    func getWritableFile(writeSize: UInt64) throws -> WritableFile
    func getReadableFiles(excludingFilesNamed excludedFileNames: Set<String>, limit: Int) -> [ReadableFile]
    func delete(readableFile: ReadableFile, deletionReason: BatchDeletedMetric.RemovalReason)

    var ignoreFilesAgeWhenReading: Bool { get set }
}

/// Orchestrates files in a single directory.
internal class FilesOrchestrator: FilesOrchestratorType {
    /// Directory where files are stored.
    let directory: Directory
    /// Date provider.
    let dateProvider: DateProvider
    /// Performance rules for writing and reading files.
    let performance: StoragePerformancePreset
    /// Name of the last file returned by `getWritableFile()`.
    private var lastWritableFileName: String? = nil
    /// Tracks number of times the last file was returned from `getWritableFile(writeSize:)`.
    /// This should correspond with number of objects stored in file, assuming that majority of writes succeed (the difference is negligible).
    private var lastWritableFileObjectsCount: UInt64 = 0
    /// Tracks the size of last writable file by accumulating the total `writeSize:` requested in `getWritableFile(writeSize:)`
    /// This is approximated value as it assumes that all requested writes succed. The actual difference should be negligible.
    private var lastWritableFileApproximatedSize: UInt64 = 0
    /// Telemetry interface.
    let telemetry: Telemetry

    /// Extra information for metrics set from this orchestrator.
    struct MetricsData {
        /// The name of the track reported for this orchestrator.
        let trackName: String
        /// The label indicating the value of tracking consent that this orchestrator manages files for.
        let consentLabel: String
        /// The preset for uploader performance in this feature to include in metric.
        let uploaderPerformance: UploadPerformancePreset
    }

    /// An extra information to include in metrics or `nil` if metrics should not be reported for this orchestrator.
    let metricsData: MetricsData?

    init(
        directory: Directory,
        performance: StoragePerformancePreset,
        dateProvider: DateProvider,
        telemetry: Telemetry,
        metricsData: MetricsData? = nil
    ) {
        self.directory = directory
        self.performance = performance
        self.dateProvider = dateProvider
        self.telemetry = telemetry
        self.metricsData = metricsData
    }

    // MARK: - `WritableFile` orchestration

    /// Returns writable file accordingly to default heuristic of creating and reusing files.
    ///
    /// - Parameter writeSize: the size of data to be written
    /// - Returns: `WritableFile` capable of writing data of given size
    func getWritableFile(writeSize: UInt64) throws -> WritableFile {
        try validate(writeSize: writeSize)

        if let lastWritableFile = reuseLastWritableFileIfPossible(writeSize: writeSize) { // if last writable file can be reused
            lastWritableFileObjectsCount += 1
            lastWritableFileApproximatedSize += writeSize
            return lastWritableFile
        } else {
            if let closedBatchName = lastWritableFileName {
                sendBatchClosedMetric(fileName: closedBatchName)
            }
            return try createNewWritableFile(writeSize: writeSize)
        }
    }

    private func validate(writeSize: UInt64) throws {
        guard writeSize <= performance.maxObjectSize else {
            throw InternalError(description: "data exceeds the maximum size of \(performance.maxObjectSize) bytes.")
        }
    }

    private func createNewWritableFile(writeSize: UInt64) throws -> WritableFile {
        // NOTE: RUMM-610 Because purging files directory is a memory-expensive operation, do it only when a new file
        // is created (we assume here that this won't happen too often). In details, this is to avoid over-allocating
        // internal `_FileCache` and `_NSFastEnumerationEnumerator` objects in downstream `FileManager` routines.
        // This optimisation results with flat allocation graph in a long term (vs endlessly growing if purging
        // happens too often).
        try purgeFilesDirectoryIfNeeded()

        let newFileName = fileNameFrom(fileCreationDate: dateProvider.now)
        let newFile = try directory.createFile(named: newFileName)
        lastWritableFileName = newFile.name
        lastWritableFileObjectsCount = 1
        lastWritableFileApproximatedSize = writeSize
        return newFile
    }

    private func reuseLastWritableFileIfPossible(writeSize: UInt64) -> WritableFile? {
        if let lastFileName = lastWritableFileName {
            if !directory.hasFile(named: lastFileName) {
                return nil // this is expected if the last writable file was deleted
            }

            do {
                let lastFile = try directory.file(named: lastFileName)
                let lastFileCreationDate = fileCreationDateFrom(fileName: lastFile.name)
                let lastFileAge = dateProvider.now.timeIntervalSince(lastFileCreationDate)

                let fileIsRecentEnough = lastFileAge <= performance.maxFileAgeForWrite
                let fileHasRoomForMore = (try lastFile.size() + writeSize) <= performance.maxFileSize
                let fileCanBeUsedMoreTimes = (lastWritableFileObjectsCount + 1) <= performance.maxObjectsInFile

                if fileIsRecentEnough && fileHasRoomForMore && fileCanBeUsedMoreTimes {
                    return lastFile
                }
            } catch {
                telemetry.error("Failed to reuse last writable file", error: error)
            }
        }

        return nil
    }

    // MARK: - `ReadableFile` orchestration

    func getReadableFiles(excludingFilesNamed excludedFileNames: Set<String> = [], limit: Int = .max) -> [ReadableFile] {
        do {
            let filesFromOldest = try directory.files()
                .map { (file: $0, creationDate: fileCreationDateFrom(fileName: $0.name)) }
                .compactMap { try deleteFileIfItsObsolete(file: $0.file, fileCreationDate: $0.creationDate) }
                .sorted(by: { $0.creationDate < $1.creationDate })

            if ignoreFilesAgeWhenReading {
                return filesFromOldest
                    .prefix(limit)
                    .map { $0.file }
            }

            let filtered = filesFromOldest
                .filter {
                    let fileAge = dateProvider.now.timeIntervalSince($0.creationDate)
                    return excludedFileNames.contains($0.file.name) == false && fileAge >= performance.minFileAgeForRead
                }
            return filtered
                .prefix(limit)
                .map { $0.file }
        } catch {
            telemetry.error("Failed to obtain readable file", error: error)
            return []
        }
    }

    func delete(readableFile: ReadableFile, deletionReason: BatchDeletedMetric.RemovalReason) {
        do {
            try readableFile.delete()
            sendBatchDeletedMetric(batchFile: readableFile, deletionReason: deletionReason)
        } catch {
            telemetry.error("Failed to delete file", error: error)
        }
    }

    /// If files age should be ignored for obtaining `ReadableFile`.
    internal var ignoreFilesAgeWhenReading = false

    // MARK: - Directory size management

    /// Removes oldest files from the directory if it becomes too big.
    private func purgeFilesDirectoryIfNeeded() throws {
        let filesSortedByCreationDate = try directory.files()
            .map { (file: $0, creationDate: fileCreationDateFrom(fileName: $0.name)) }
            .sorted { $0.creationDate < $1.creationDate }

        var filesWithSizeSortedByCreationDate = try filesSortedByCreationDate
            .map { (file: $0.file, size: try $0.file.size()) }

        let accumulatedFilesSize = filesWithSizeSortedByCreationDate.map { $0.size }.reduce(0, +)

        if accumulatedFilesSize > performance.maxDirectorySize {
            let sizeToFree = accumulatedFilesSize - performance.maxDirectorySize
            var sizeFreed: UInt64 = 0

            while sizeFreed < sizeToFree && !filesWithSizeSortedByCreationDate.isEmpty {
                let fileWithSize = filesWithSizeSortedByCreationDate.removeFirst()
                try fileWithSize.file.delete()
                sendBatchDeletedMetric(batchFile: fileWithSize.file, deletionReason: .purged)
                sizeFreed += fileWithSize.size
            }
        }
    }

    private func deleteFileIfItsObsolete(file: File, fileCreationDate: Date) throws -> (file: File, creationDate: Date)? {
        let fileAge = dateProvider.now.timeIntervalSince(fileCreationDate)

        if fileAge > performance.maxFileAgeForRead {
            try file.delete()
            sendBatchDeletedMetric(batchFile: file, deletionReason: .obsolete)
            return nil
        } else {
            return (file: file, creationDate: fileCreationDate)
        }
    }

    // MARK: - Metrics

    /// Sends "Batch Deleted" telemetry log.
    /// - Parameters:
    ///   - batchFile: The batch file that was deleted.
    ///   - deletionReason: The reason of deleting this file.
    ///
    /// Note: The `batchFile` doesn't exist at this point.
    private func sendBatchDeletedMetric(batchFile: ReadableFile, deletionReason: BatchDeletedMetric.RemovalReason) {
        guard let metricsData = metricsData, deletionReason.includeInMetric else {
            return // do not track metrics for this orchestrator or deletion reason
        }

        let batchAge = dateProvider.now.timeIntervalSince(fileCreationDateFrom(fileName: batchFile.name))

        telemetry.metric(
            name: BatchDeletedMetric.name,
            attributes: [
                BasicMetric.typeKey: BatchDeletedMetric.typeValue,
                BatchMetric.trackKey: metricsData.trackName,
                BatchDeletedMetric.uploaderDelayKey: [
                    BatchDeletedMetric.uploaderDelayMinKey: metricsData.uploaderPerformance.minUploadDelay.toMilliseconds,
                    BatchDeletedMetric.uploaderDelayMaxKey: metricsData.uploaderPerformance.maxUploadDelay.toMilliseconds,
                ],
                BatchMetric.consentKey: metricsData.consentLabel,
                BatchDeletedMetric.uploaderWindowKey: performance.uploaderWindow.toMilliseconds,
                BatchDeletedMetric.batchAgeKey: batchAge.toMilliseconds,
                BatchDeletedMetric.batchRemovalReasonKey: deletionReason.toString(),
                BatchDeletedMetric.inBackgroundKey: false
            ]
        )
    }

    /// Sends "Batch Closed" telemetry log.
    /// - Parameters:
    ///   - fileName: The name of the batch that was closed.
    private func sendBatchClosedMetric(fileName: String) {
        guard let metricsData = metricsData else {
            return // do not track metrics for this orchestrator
        }

        let batchDuration = dateProvider.now.timeIntervalSince(fileCreationDateFrom(fileName: fileName))

        telemetry.metric(
            name: BatchClosedMetric.name,
            attributes: [
                BasicMetric.typeKey: BatchClosedMetric.typeValue,
                BatchMetric.trackKey: metricsData.trackName,
                BatchMetric.consentKey: metricsData.consentLabel,
                BatchClosedMetric.uploaderWindowKey: performance.uploaderWindow.toMilliseconds,
                BatchClosedMetric.batchSizeKey: lastWritableFileApproximatedSize,
                BatchClosedMetric.batchEventsCountKey: lastWritableFileObjectsCount,
                BatchClosedMetric.batchDurationKey: batchDuration.toMilliseconds
            ]
        )
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
