import Foundation

/// Creates and owns components necessary for logs persistence.
internal struct LogsPersistenceStrategy {
    struct Constants {
        /// Subdirectory in `/Library/Caches` where log files are stored.
        static let logFilesSubdirectory: String = "com.datadoghq.logs/v1"
        /// Maximum size of batched logs in single file (in bytes).
        /// If last written file is too big to append next log data, new file is created.
        static let maxBatchSize: UInt64 = 4 * 1_024 * 1_024
        /// Maximum age of logs file for file reuse (in seconds).
        /// If last written file is older than this, new file is created to store next log data.
        static let maxFileAgeForWrite: TimeInterval = 4.75
        /// Minimum age of logs file to be picked for upload (in seconds).
        /// It has the arbitrary offset (0.5s) over `maxFileAgeForWrite` to ensure that no upload is started for file being written.
        static let minFileAgeForRead: TimeInterval = maxFileAgeForWrite + 0.5
        /// Maximum number of logs written to single file.
        /// If number of logs in last written file reaches this limit, new file is created to store next log data.
        static let maxLogsPerBatch: Int = 500
        /// Maximum size of serialized log data.
        /// If JSON encoded `Log` exceeds this size, it is dropped (not written to file).
        static let maxLogSize: Int = 256 * 1_024
    }

    /// Default write conditions for `FilesOrchestrator`.
    static let defaultWriteConditions = WritableFileConditions(
        maxFileSize: LogsPersistenceStrategy.Constants.maxBatchSize,
        maxFileAgeForWrite: LogsPersistenceStrategy.Constants.maxFileAgeForWrite,
        maxNumberOfUsesOfFile: LogsPersistenceStrategy.Constants.maxLogsPerBatch
    )

    /// Default read conditions for `FilesOrchestrator`.
    static let defaultReadConditions = ReadableFileConditions(
        minFileAgeForRead: LogsPersistenceStrategy.Constants.minFileAgeForRead
    )

    /// Default strategy which uses single GCD queue for read and write file access.
    /// TODO: RUMM-140 Check with performance tests if it's worth introducing another thread
    static func `defalut`(using dateProvider: DateProvider) throws -> LogsPersistenceStrategy {
        let directory = try Directory(withSubdirectoryPath: Constants.logFilesSubdirectory)
        return defalut(in: directory, dateProvider: dateProvider)
    }

    static func `defalut`(in directory: Directory, dateProvider: DateProvider) -> LogsPersistenceStrategy {
        let orchestrator = FilesOrchestrator(
            directory: directory,
            writeConditions: defaultWriteConditions,
            readConditions: defaultReadConditions,
            dateProvider: dateProvider
        )

        let readWriteQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-logs-read-write",
            target: .global(qos: .utility)
        )

        return LogsPersistenceStrategy(
            writer: FileWriter(
                orchestrator: orchestrator,
                queue: readWriteQueue,
                maxWriteSize: Constants.maxLogSize
            ),
            reader: FileReader(
                orchestrator: orchestrator,
                queue: readWriteQueue
            )
        )
    }

    /// Writes logs to files.
    let writer: FileWriter

    /// Reads logs from files.
    let reader: FileReader
}
