/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Abstracts the `DataUploadWorker`, so we can have no-op uploader in tests.
internal protocol DataUploadWorkerType: Sendable {
    func flush() async
    func cancel() async
}

internal actor DataUploadWorker: DataUploadWorkerType {
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
    /// Maximum number of batches to upload per cycle.
    private let maxBatchesPerUpload: Int

    /// Telemetry interface.
    private let telemetry: Telemetry

    /// Background task coordinator responsible for registering and ending background tasks for UIKit targets.
    private var backgroundTaskCoordinator: BackgroundTaskCoordinator?

    private var previousUploadStatus: DataUploadStatus?

    /// The upload loop task.
    private var loopTask: Task<Void, Never>?

    init(
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
        self.fileReader = fileReader
        self.uploadConditions = uploadConditions
        self.dataUploader = dataUploader
        self.contextProvider = contextProvider
        self.backgroundTaskCoordinator = backgroundTaskCoordinator
        self.delay = delay
        self.featureName = featureName
        self.telemetry = telemetry
        self.maxBatchesPerUpload = maxBatchesPerUpload
    }

    /// Starts the upload loop with an initial jitter delay.
    func start() {
        loopTask = Task {
            let jitter: TimeInterval = .random(in: 0...delay.maxJitter)
            if jitter > 0 {
                try? await Task.sleep(nanoseconds: UInt64(jitter * 1_000_000_000))
            }

            while !Task.isCancelled {
                await performUploadCycle()
                let sleepDuration = delay.current
                try? await Task.sleep(nanoseconds: UInt64(sleepDuration * 1_000_000_000))
            }
        }
    }

    /// Cancels the upload loop.
    func cancel() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Cancels the upload loop and uploads all remaining data.
    func flush() async {
        cancel()

        for file in await fileReader.readFiles(limit: .max) {
            guard let nextBatch = fileReader.readBatch(from: file) else {
                continue
            }
            defer {
                previousUploadStatus = nil
            }
            do {
                previousUploadStatus = try dataUploader.upload(
                    events: nextBatch.events,
                    context: contextProvider.read(),
                    previous: previousUploadStatus
                )
            } catch {
                previousUploadStatus = try? dataUploader.upload(
                    events: nextBatch.events,
                    context: contextProvider.read(),
                    previous: previousUploadStatus
                )
            }
            await fileReader.markBatchAsRead(nextBatch, reason: .flushed)
        }
    }

#if DD_SDK_COMPILED_FOR_TESTING
    /// Exposes the current upload delay for testing.
    var currentUploadDelay: TimeInterval {
        delay.current
    }
#endif

    // MARK: - Private

    private func performUploadCycle() async {
        let context = contextProvider.read()
        let blockersForUpload = uploadConditions.blockersForUpload(with: context)
        let isSystemReady = blockersForUpload.isEmpty
        let files = isSystemReady ? await fileReader.readFiles(limit: maxBatchesPerUpload) : nil

        if let files = files, !files.isEmpty {
            DD.logger.debug("⏳ (\(featureName)) Uploading batches...")
            await backgroundTaskCoordinator?.beginBackgroundTask()
            await uploadBatches(from: files.reversed(), context: context)
        } else {
            let batchLabel = files?.isEmpty == false ? "YES" : (isSystemReady ? "NO" : "NOT CHECKED")
            let conditionsDescription = blockersForUpload.description
            DD.logger.debug("💡 (\(featureName)) No upload. Batch to upload: \(batchLabel), System conditions: \(conditionsDescription)")
            delay.increase()
            await backgroundTaskCoordinator?.endBackgroundTask()
            sendUploadQualityMetric(blockers: blockersForUpload)
        }
    }

    private func uploadBatches(from files: [ReadableFile], context: DatadogContext) async {
        var files = files
        while let file = files.popLast() {
            if let batch = fileReader.readBatch(from: file) {
                do {
                    let uploadStatus = try dataUploader.upload(
                        events: batch.events,
                        context: context,
                        previous: previousUploadStatus
                    )

                    previousUploadStatus = uploadStatus
                    sendUploadQualityMetric(status: uploadStatus)

                    if uploadStatus.needsRetry {
                        DD.logger.debug("   → (\(featureName)) not delivered, will be retransmitted: \(uploadStatus.userDebugDescription)")
                        delay.increase()
                        return
                    }

                    DD.logger.debug("   → (\(featureName)) accepted, won't be retransmitted: \(uploadStatus.userDebugDescription)")
                    if files.isEmpty {
                        delay.reset()
                    }

                    await fileReader.markBatchAsRead(
                        batch,
                        reason: .intakeCode(responseCode: uploadStatus.responseCode)
                    )
#if DD_BENCHMARK
                    bench.meter.counter(metric: "ios.benchmark.upload_count")
                        .increment(attributes: ["track": featureName])
#endif

                    previousUploadStatus = nil

                    if let error = uploadStatus.error {
                        throw error
                    }
                } catch DataUploadError.httpError(statusCode: .unauthorized), DataUploadError.httpError(statusCode: .forbidden) {
                    DD.logger.error("⚠️ Make sure that the provided token still exists and you're targeting the relevant Datadog site.")
                } catch DataUploadError.httpError(statusCode: let statusCode) where !telemetryIgnoredStatusCodes.contains(statusCode) {
                    telemetry.error("Data upload finished with status code: \(statusCode.rawValue)")
                } catch DataUploadError.networkError(let error) where !telemetryIgnoredNSURLErrorCodes.contains(error.code) {
                    telemetry.error("Data upload finished with error", error: error)
                } catch is DataUploadError {
                    // Do not report any other 'DataUploadError':
                    // - If status indicate Datadog service issue, there is no fix required client side.
                    // - If status code is unexpected, monitoring may become too verbose for old installations
                    // if we introduce a new status code in the API.
                } catch let error {
                    await fileReader.markBatchAsRead(batch, reason: .invalid)
                    previousUploadStatus = nil
                    telemetry.error("Failed to initiate '\(featureName)' data upload", error: error)
                    sendUploadQualityMetric(failure: "invalid")
                }
            }
        }
    }

    // MARK: - Metrics

    private func sendUploadQualityMetric(blockers: [DataUploadConditions.Blocker]) {
        guard !blockers.isEmpty else {
            return sendUploadQualityMetric()
        }

        sendUploadQualityMetric(
            failure: "blocker",
            blockers: blockers.map {
                switch $0 {
                case .battery: return "low_battery"
                case .lowPowerModeOn: return "lpm"
                case .networkReachability: return "offline"
                }
            }
        )
    }

    private func sendUploadQualityMetric(status: DataUploadStatus) {
        guard let error = status.error else {
            return sendUploadQualityMetric()
        }

        sendUploadQualityMetric(
            failure: {
                switch error {
                case let .httpError(code): return "\(code)"
                case let .networkError(error): return "\(error.code)"
                }
            }()
        )
    }

    private func sendUploadQualityMetric() {
        telemetry.metric(
            name: UploadQualityMetric.name,
            attributes: [
                UploadQualityMetric.track: featureName
            ]
        )
    }

    private func sendUploadQualityMetric(failure: String, blockers: [String] = []) {
        telemetry.metric(
            name: UploadQualityMetric.name,
            attributes: [
                UploadQualityMetric.track: featureName,
                UploadQualityMetric.failure: failure,
                UploadQualityMetric.blockers: blockers
            ]
        )
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
