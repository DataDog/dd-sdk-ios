import Foundation

internal class DataUploadWorker {
    /// Queue to execute uploads.
    private let queue: DispatchQueue
    /// File reader providing data to upload.
    private let fileReader: FileReader
    /// Data uploader sending data to server..
    private let dataUploader: DataUploader
    /// For each file upload, the status is checked against this list of acceptable statuses.
    /// If it's there, the file will be deleted. If not, it will be retried in next upload.
    private let acceptableUploadStatuses: Set<DataUploadStatus> = [
        .success, .redirection, .clientError, .unknown
    ]

    /// Delay used to schedule consecutive uploads.
    private var delay: DataUploadDelay

    init(queue: DispatchQueue, fileReader: FileReader, dataUploader: DataUploader, delay: DataUploadDelay) {
        self.queue = queue
        self.fileReader = fileReader
        self.dataUploader = dataUploader
        self.delay = delay

        scheduleNextUpload(after: self.delay.nextUploadDelay())
    }

    private func scheduleNextUpload(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            developerLogger?.info("⏳ Checking for next batch...")

            guard let self = self else {
                return
            }

            if self.shouldPerformUpload(), let batch = self.fileReader.readNextBatch() {
                developerLogger?.info("⏳ Uploading batch...")
                userLogger.debug("⏳ Uploading batch...")

                let uploadStatus = self.dataUploader.upload(data: batch.data)
                let shouldBeAccepted = self.acceptableUploadStatuses.contains(uploadStatus)

                if shouldBeAccepted {
                    self.fileReader.markBatchAsRead(batch)
                    developerLogger?.info("   → accepted, won't be retransmitted: \(uploadStatus)")
                    userLogger.debug("   → accepted, won't be retransmitted: \(uploadStatus)")
                } else {
                    developerLogger?.info("  → not delivered, will be retransmitted: \(uploadStatus)")
                    userLogger.debug("   → not delivered, will be retransmitted: \(uploadStatus)")
                }

                self.delay.decrease()
            } else {
                developerLogger?.info("💡 No batch to upload.")
                userLogger.debug("💡 No batch to upload.")
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
