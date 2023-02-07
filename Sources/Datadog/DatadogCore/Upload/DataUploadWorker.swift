/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Abstracts the `DataUploadWorker`, so we can have no-op uploader in tests.
internal protocol DataUploadWorkerType {
    func flushSynchronously()
    func cancelSynchronously()
}

internal class DataUploadWorker: DataUploadWorkerType {
    /// Queue to execute uploads.
    private let queue: DispatchQueue
    /// File reader providing data to upload.
    private let fileReader: Reader
    /// Data uploader sending data to server.
    private let dataUploader: DataUploaderType
    /// Variable system conditions determining if upload should be performed.
    private let uploadConditions: DataUploadConditions
    /// Name of the feature this worker is performing uploads for.
    private let featureName: String

    /// The core context provider
    private let contextProvider: DatadogContextProvider

    /// Delay used to schedule consecutive uploads.
    private var delay: Delay

    /// Upload work scheduled by this worker.
    private var uploadWork: DispatchWorkItem?

    init(
        queue: DispatchQueue,
        fileReader: Reader,
        dataUploader: DataUploaderType,
        contextProvider: DatadogContextProvider,
        uploadConditions: DataUploadConditions,
        delay: Delay,
        featureName: String
    ) {
        self.queue = queue
        self.fileReader = fileReader
        self.uploadConditions = uploadConditions
        self.dataUploader = dataUploader
        self.contextProvider = contextProvider
        self.delay = delay
        self.featureName = featureName

        let uploadWork = DispatchWorkItem { [weak self] in
            guard let self = self else {
                return
            }

            let context = contextProvider.read()
            let blockersForUpload = self.uploadConditions.blockersForUpload(with: context)
            let isSystemReady = blockersForUpload.isEmpty
            let nextBatch = isSystemReady ? self.fileReader.readNextBatch() : nil
            if let batch = nextBatch {
                DD.logger.debug("⏳ (\(self.featureName)) Uploading batch...")

                do {
                    // Upload batch
                    let uploadStatus = try self.dataUploader.upload(
                        events: batch.events,
                        context: context
                    )

                    // Delete or keep batch depending on the upload status
                    if uploadStatus.needsRetry {
                        self.delay.increase()

                        DD.logger.debug("   → (\(self.featureName)) not delivered, will be retransmitted: \(uploadStatus.userDebugDescription)")
                    } else {
                        self.fileReader.markBatchAsRead(batch)
                        self.delay.decrease()

                        DD.logger.debug("   → (\(self.featureName)) accepted, won't be retransmitted: \(uploadStatus.userDebugDescription)")
                    }

                    switch uploadStatus.error {
                    case .unauthorized:
                        DD.logger.error("⚠️ Make sure that the provided token still exists and you're targeting the relevant Datadog site.")
                    case let .httpError(statusCode: statusCode):
                        DD.telemetry.error("Data upload finished with status code: \(statusCode)")
                    case let .networkError(error: error):
                        DD.telemetry.error("Data upload finished with error", error: error)
                    case .none: break
                    }
                } catch let error {
                    // If upload can't be initiated do not retry, so drop the batch:
                    self.fileReader.markBatchAsRead(batch)
                    DD.telemetry.error("Failed to initiate '\(self.featureName)' data upload", error: error)
                }
            } else {
                let batchLabel = nextBatch != nil ? "YES" : (isSystemReady ? "NO" : "NOT CHECKED")
                DD.logger.debug("💡 (\(self.featureName)) No upload. Batch to upload: \(batchLabel), System conditions: \(blockersForUpload.description)")

                self.delay.increase()
            }

            self.scheduleNextUpload(after: self.delay.current)
        }

        self.uploadWork = uploadWork

        scheduleNextUpload(after: self.delay.current)
    }

    private func scheduleNextUpload(after delay: TimeInterval) {
        guard let work = uploadWork else {
            return
        }

        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Sends all unsent data synchronously.
    /// - It performs arbitrary upload (without checking upload condition and without re-transmitting failed uploads).
    internal func flushSynchronously() {
        queue.sync {
            while let nextBatch = self.fileReader.readNextBatch() {
                _ = try? self.dataUploader.upload(events: nextBatch.events, context: contextProvider.read())
                self.fileReader.markBatchAsRead(nextBatch)
            }
        }
    }

    /// Cancels scheduled uploads and stops scheduling next ones.
    /// - It does not affect the upload that has already begun.
    /// - It blocks the caller thread if called in the middle of upload execution.
    internal func cancelSynchronously() {
        queue.sync {
            // This cancellation must be performed on the `queue` to ensure that it is not called
            // in the middle of a `DispatchWorkItem` execution - otherwise, as the pending block would be
            // fully executed, it will schedule another upload by calling `nextScheduledWork(after:)` at the end.
            self.uploadWork?.cancel()
            self.uploadWork = nil
        }
    }
}

extension DataUploadConditions.Blocker: CustomStringConvertible {
    var description: String {
        switch self {
        case let .battery(level: level, state: state):
            return "🔋 Battery state is: \(state) (\(level)%)"
        case .lowPowerModeOn:
            return "🔌 Low Power Mode is: enabled"
        case let .networkReachability(description: description):
            return "📡 Network reachability is: " + description
        }
    }
}

fileprivate extension Array where Element == DataUploadConditions.Blocker {
    var description: String {
        if self.isEmpty {
            return "✅"
        } else {
            return "❌ [upload was skipped because: " + self.map { $0.description }.joined(separator: " AND ") + "]"
        }
    }
}
