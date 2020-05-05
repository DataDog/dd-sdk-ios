/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class DataUploadWorker {
    /// Queue to execute uploads.
    private let queue: DispatchQueue
    /// File reader providing data to upload.
    private let fileReader: FileReader
    /// Data uploader sending data to server.
    private let dataUploader: DataUploader
    /// Variable system conditions determining if upload should be performed.
    private let uploadConditions: DataUploadConditions
    /// For each file upload, the status is checked against this list of acceptable statuses.
    /// If it's there, the file will be deleted. If not, it will be retried in next upload.
    private let acceptableUploadStatuses: Set<DataUploadStatus> = [
        .success, .redirection, .clientError, .unknown
    ]
    /// Name of the feature this worker is performing uploads for.
    private let featureName: String

    /// Delay used to schedule consecutive uploads.
    private var delay: DataUploadDelay

    init(
        queue: DispatchQueue,
        fileReader: FileReader,
        dataUploader: DataUploader,
        uploadConditions: DataUploadConditions,
        delay: DataUploadDelay,
        featureName: String
    ) {
        self.queue = queue
        self.fileReader = fileReader
        self.uploadConditions = uploadConditions
        self.dataUploader = dataUploader
        self.delay = delay
        self.featureName = featureName

        scheduleNextUpload(after: self.delay.nextUploadDelay())
    }

    private func scheduleNextUpload(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else {
                return
            }

            developerLogger?.info("⏳ (\(self.featureName)) Checking for next batch...")

            let isSystemReady = self.uploadConditions.canPerformUpload()
            let nextBatch = isSystemReady ? self.fileReader.readNextBatch() : nil

            if let batch = nextBatch {
                developerLogger?.info("⏳ (\(self.featureName)) Uploading batch...")
                userLogger.debug("⏳ (\(self.featureName)) Uploading batch...")

                let uploadStatus = self.dataUploader.upload(data: batch.data)
                let shouldBeAccepted = self.acceptableUploadStatuses.contains(uploadStatus)

                if shouldBeAccepted {
                    self.fileReader.markBatchAsRead(batch)
                    developerLogger?.info("   → (\(self.featureName)) accepted, won't be retransmitted: \(uploadStatus)")
                    userLogger.debug("   → (\(self.featureName)) accepted, won't be retransmitted: \(uploadStatus)")
                } else {
                    developerLogger?.info("  → (\(self.featureName)) not delivered, will be retransmitted: \(uploadStatus)")
                    userLogger.debug("   → (\(self.featureName)) not delivered, will be retransmitted: \(uploadStatus)")
                }

                self.delay.decrease()
            } else {
                let batchLabel = nextBatch != nil ? "YES" : (isSystemReady ? "NO" : "NOT CHECKED")
                let systemLabel = isSystemReady ? "✅" : "❌"
                developerLogger?.info("💡 (\(self.featureName)) No upload. Batch to upload: \(batchLabel), System conditions: \(systemLabel)")
                userLogger.debug("💡 (\(self.featureName)) No upload. Batch to upload: \(batchLabel), System conditions: \(systemLabel)")

                self.delay.increaseOnce()
            }

            self.scheduleNextUpload(after: self.delay.nextUploadDelay())
        }
    }
}
