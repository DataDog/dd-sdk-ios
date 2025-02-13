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
    private let delay: DataUploadDelay
    /// Maximum number of batches to upload in one request.
    private let maxBatchesPerUpload: Int

    /// Batch reading work scheduled by this worker.
    @ReadWriteLock
    private var readWork: DispatchWorkItem?
    /// Batch upload work scheduled by this worker.
    @ReadWriteLock
    private var uploadWork: DispatchWorkItem?

    /// Telemetry interface.
    private let telemetry: Telemetry

    /// Background task coordinator responsible for registering and ending background tasks for UIKit targets.
    private var backgroundTaskCoordinator: BackgroundTaskCoordinator?

    private var previousUploadStatus: DataUploadStatus?

    init(
        queue: DispatchQueue,
        fileReader: Reader,
        dataUploader: DataUploaderType,
        contextProvider: DatadogContextProvider,
        uploadConditions: DataUploadConditions,
        delay: DataUploadDelay,
        featureName: String,
        telemetry: Telemetry,
        maxBatchesPerUpload: Int,
        backgroundTaskCoordinator: BackgroundTaskCoordinator? = nil
    ) {
        self.queue = queue
        self.fileReader = fileReader
        self.uploadConditions = uploadConditions
        self.dataUploader = dataUploader
        self.contextProvider = contextProvider
        self.backgroundTaskCoordinator = backgroundTaskCoordinator
        self.delay = delay
        self.maxBatchesPerUpload = maxBatchesPerUpload
        self.featureName = featureName
        self.telemetry = telemetry
        let readWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else {
                return
            }
            let context = contextProvider.read()
            let blockersForUpload = uploadConditions.blockersForUpload(with: context)
            let isSystemReady = blockersForUpload.isEmpty
            let files = isSystemReady ? fileReader.readFiles(limit: maxBatchesPerUpload) : nil
            if let files = files, !files.isEmpty {
                DD.logger.debug("⏳ (\(self.featureName)) Uploading batches...")
                self.backgroundTaskCoordinator?.beginBackgroundTask()
                self.uploadFile(from: files.reversed(), context: context)
            } else {
                let batchLabel = files?.isEmpty == false ? "YES" : (isSystemReady ? "NO" : "NOT CHECKED")
                DD.logger.debug("💡 (\(self.featureName)) No upload. Batch to upload: \(batchLabel), System conditions: \(blockersForUpload.description)")
                self.delay.increase()
                self.backgroundTaskCoordinator?.endBackgroundTask()
                self.scheduleNextCycle()
            }
        }
        self.readWork = readWorkItem

        // Start sending batches immediately after initialization:
        queue.async(execute: readWorkItem)
    }

    private func scheduleNextCycle() {
        guard let readWork = self.readWork else {
            return
        }
        queue.asyncAfter(deadline: .now() + delay.current, execute: readWork)
    }

    private func uploadFile(from files: [ReadableFile], context: DatadogContext) {
        let uploadWork = DispatchWorkItem { [weak self] in
            guard let self = self else {
                return
            }
            var files = files
            guard let file = files.popLast() else {
                self.scheduleNextCycle()
                return
            }
            if let batch = self.fileReader.readBatch(from: file) {
                do {
                    let uploadStatus = try self.dataUploader.upload(
                        events: batch.events,
                        context: context,
                        previous: previousUploadStatus
                    )
                    previousUploadStatus = uploadStatus

                    if uploadStatus.needsRetry {
                        DD.logger.debug("   → (\(self.featureName)) not delivered, will be retransmitted: \(uploadStatus.userDebugDescription)")
                        self.delay.increase()
                        self.scheduleNextCycle()
                        return
                    }

                    DD.logger.debug("   → (\(self.featureName)) accepted, won't be retransmitted: \(uploadStatus.userDebugDescription)")
                    if files.isEmpty {
                        self.delay.decrease()
                    }

                    self.fileReader.markBatchAsRead(
                        batch,
                        reason: .intakeCode(responseCode: uploadStatus.responseCode)
                    )

                    previousUploadStatus = nil

                    if let error = uploadStatus.error {
                        // Throw to report the request error accordingly
                        throw error
                    }

                } catch DataUploadError.httpError(statusCode: .unauthorized), DataUploadError.httpError(statusCode: .forbidden) {
                    DD.logger.error("⚠️ Make sure that the provided token still exists and you're targeting the relevant Datadog site.")
                } catch DataUploadError.httpError(statusCode: let statusCode) where !telemetryIgnoredStatusCodes.contains(statusCode) {
                    self.telemetry.error("Data upload finished with status code: \(statusCode.rawValue)")
                } catch DataUploadError.networkError(let error) where !telemetryIgnoredNSURLErrorCodes.contains(error.code) {
                    self.telemetry.error("Data upload finished with error", error: error)
                } catch is DataUploadError {
                    // Do not report any other 'DataUploadError':
                    // - If status indicate Datadog service issue, there is no fix required client side.
                    // - If status code is unexpected, monitoring may become too verbose for old installations
                    // if we introduce a new status code in the API.
                } catch let error {
                    // If upload can't be initiated do not retry, so drop the batch:
                    self.fileReader.markBatchAsRead(batch, reason: .invalid)
                    previousUploadStatus = nil
                    self.telemetry.error("Failed to initiate '\(self.featureName)' data upload", error: error)
                }
            }
            if files.isEmpty {
                self.scheduleNextCycle()
            } else {
                self.uploadFile(from: files, context: context)
            }
        }
        self.uploadWork = uploadWork
        queue.async(execute: uploadWork)
    }

    /// Sends all unsent data synchronously.
    /// - It performs arbitrary upload (without checking upload condition and without re-transmitting failed uploads).
    internal func flushSynchronously() {
        queue.sync { [weak self] in
            guard let self = self else {
                return
            }
            for file in self.fileReader.readFiles(limit: .max) {
                guard let nextBatch = self.fileReader.readBatch(from: file) else {
                    continue
                }
                defer {
                    // RUMM-3459 Delete the underlying batch with `.flushed` reason that will be ignored in reported
                    // metrics or telemetry. This is legitimate as long as `flush()` routine is only available for testing
                    // purposes and never run in production apps.
                    self.fileReader.markBatchAsRead(nextBatch, reason: .flushed)
                    previousUploadStatus = nil
                }
                do {
                    // Try uploading the batch and do one more retry on failure.
                    previousUploadStatus = try self.dataUploader.upload(
                        events: nextBatch.events,
                        context: self.contextProvider.read(),
                        previous: previousUploadStatus
                    )
                } catch {
                    previousUploadStatus = try? self.dataUploader.upload(
                        events: nextBatch.events,
                        context: self.contextProvider.read(),
                        previous: previousUploadStatus
                    )
                }
            }
        }
    }

    /// Cancels scheduled uploads and stops scheduling next ones.
    /// - It does not affect the upload that has already begun.
    /// - It blocks the caller thread if called in the middle of upload execution.
    internal func cancelSynchronously() {
        queue.sync { [weak self] in
            guard let self = self else {
                return
            }
            // This cancellation must be performed on the `queue` to ensure that it is not called
            // in the middle of a `DispatchWorkItem` execution - otherwise, as the pending block would be
            // fully executed, it will schedule another upload by calling `nextScheduledWork(after:)` at the end.
            self.uploadWork?.cancel()
            self.uploadWork = nil
            self.readWork?.cancel()
            self.readWork = nil
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
            return "❌ [upload was skipped because: " + map {
                $0.description
            }.joined(separator: " AND ") + "]"
        }
    }
}

/// A list of known NSURLError codes which should not produce error in Telemetry.
/// Receiving these codes doesn't mean SDK issue, but the network transportation scenario where the connection interrupted due to external factors.
/// These list should evolve and we may want to add more codes in there.
///
/// Ref.: https://developer.apple.com/documentation/foundation/1508628-url_loading_system_error_codes
private let telemetryIgnoredNSURLErrorCodes: Set<Int> = [
    NSURLErrorNetworkConnectionLost, // -1005
    NSURLErrorTimedOut, // -1001
    NSURLErrorCannotParseResponse, // - 1017
    NSURLErrorNotConnectedToInternet, // -1009
    NSURLErrorCannotFindHost, // -1003
    NSURLErrorSecureConnectionFailed, // -1200
    NSURLErrorDataNotAllowed, // -1020
    NSURLErrorCannotConnectToHost, // -1004
]

/// These codes indicate Datadog service issue - so do not produce error as there is no fix reqiured for SDK.
private let telemetryIgnoredStatusCodes: Set<HTTPResponseStatusCode> = [
    .internalServerError,
    .serviceUnavailable,
    .badGateway,
    .gatewayTimeout,
    .insufficientStorage
]
