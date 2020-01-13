import Foundation

/// Creates and owns components necessary for logs upload.
internal struct LogsUploadStrategy {
    struct Constants {
        /// Default time interval for logs upload (in seconds).
        /// At runtime, the upload interval range from `minLogsUploadDelay` to `maxLogsUploadDelay` depending
        /// on logs delivery success / failure.
        static let defaultLogsUploadDelay: TimeInterval = 5
        /// Mininum time interval for logs upload (in seconds).
        /// By default logs are uploaded with `defaultLogsUploadDelay` which might change depending
        /// on logs delivery success / failure.
        static let minLogsUploadDelay: TimeInterval = 1
        /// Maximum time interval for logs upload (in seconds).
        /// By default logs are uploaded with `defaultLogsUploadDelay` which might change depending
        /// on logs delivery success / failure.
        static let maxLogsUploadDelay: TimeInterval = defaultLogsUploadDelay * 4
        /// Change factor of logs upload interval due to upload success.
        static let logsUploadDelayDecreaseFactor: Double = 0.9
    }

    /// Default logs upload delay.
    static let defaultLogsUploadDelay = DataUploadDelay(
        default: Constants.defaultLogsUploadDelay,
        min: Constants.minLogsUploadDelay,
        max: Constants.maxLogsUploadDelay,
        decreaseFactor: Constants.logsUploadDelayDecreaseFactor
    )

    static func `defalut`(endpointURL: String, clientToken: String, reader: FileReader) throws -> LogsUploadStrategy {
        let uploadURL = try DataUploadURL(endpointURL: endpointURL, clientToken: clientToken)
        let httpClient = HTTPClient()
        let dataUploader = DataUploader(url: uploadURL, httpClient: httpClient)
        return self.defalut(dataUploader: dataUploader, reader: reader)
    }

    static func `defalut`(
        dataUploader: DataUploader,
        reader: FileReader,
        uploadDelay: DataUploadDelay = defaultLogsUploadDelay
    ) -> LogsUploadStrategy {
        let uploadQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-logs-upload",
            target: .global(qos: .utility)
        )

        return LogsUploadStrategy(
            uploadWorker: DataUploadWorker(
                queue: uploadQueue,
                fileReader: reader,
                dataUploader: dataUploader,
                delay: uploadDelay
            )
        )
    }

    /// Uploads data to server with dynamic time intervals.
    let uploadWorker: DataUploadWorker
}
