import Foundation

internal class LogsUploader {
    /// Queue to execute uploads.
    private let queue: DispatchQueue
    /// File reader pointing to logs directory.
    private let fileReader: FileReader
    /// Data uploader.
    private let dataUploader: DataUploader
    /// For each file upload, the status is checked against this list of acceptable statuses.
    /// If it's there, the file will be deleted. If not, it will be retried in next upload.
    private let acceptableUploadStatuses: Set<DataUploadStatus> = [
        .success, .redirection, .clientError, .unknown
    ]

    /// Delay used to schedule consecutive uploads.
    private var delay: LogsUploadDelay

    init(queue: DispatchQueue, fileReader: FileReader, dataUploader: DataUploader, delay: LogsUploadDelay) {
        self.queue = queue
        self.fileReader = fileReader
        self.dataUploader = dataUploader
        self.delay = delay

        scheduleNextUpload(after: self.delay.nextUploadDelay())
    }

    private func scheduleNextUpload(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            print("Will check for next batch...")

            guard let self = self else {
                return
            }

            if self.shouldPerformUpload(), let batch = self.fileReader.readNextBatch() {
                print("Will upload batch... (current time: \(Date())")

                let uploadStatus = self.dataUploader.upload(data: batch.data)
                let wasDelivered = self.acceptableUploadStatuses.contains(uploadStatus)

                print("   -> \(uploadStatus)")

                if wasDelivered {
                    self.fileReader.markBatchAsRead(batch)
                }

                self.delay.decrease()
            } else {
                print("No batch to upload.")
                self.delay.increaseOnce()
            }

            self.scheduleNextUpload(after: self.delay.nextUploadDelay())
        }
    }

    /// TODO: RUMM-177 Skip logs uploads on certain battery and network conditions
    private func shouldPerformUpload() -> Bool {
        return true
    }
}
