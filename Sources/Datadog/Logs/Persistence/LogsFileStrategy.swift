import Foundation

internal struct LogsFileStrategy {
    struct Constants {
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
        /// If JSON encoded `Log` exceeds this size, it is dropped.
        static let maxLogSize: Int = 256 * 1_024
    }

    /// TODO: RUMM-109 Send messages from persistent storage
    // func getLogsFileWritter() throws -> FileWritter

    /// TODO: RUMM-109 Send messages from persistent storage
    // func getLogsFileReader() throws -> FileReader
}
