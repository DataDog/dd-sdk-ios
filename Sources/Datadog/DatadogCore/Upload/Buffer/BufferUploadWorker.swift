/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal final class BufferUploadWorker {

    /// Name of the feature this worker is performing uploads for.
    let name: String
    let queue: DispatchQueue
    let reader: BufferReader
    let requestBuilder: FeatureRequestBuilder_
    let httpClient: HTTPClient
    let performance: PerformancePreset
    let contextProvider: DatadogContextProvider
    let uploadConditions: DataUploadConditions
    private var delay: Delay

    /// Upload work scheduled by this worker.
    private var work: DispatchWorkItem?

    init(
        feature name: String,
        queue: DispatchQueue,
        reader: BufferReader,
        requestBuilder: FeatureRequestBuilder_,
        httpClient: HTTPClient,
        performance: PerformancePreset,
        contextProvider: DatadogContextProvider,
        uploadConditions: DataUploadConditions,
        delay: Delay
    ) {
        self.name = name
        self.queue = queue
        self.reader = reader
        self.requestBuilder = requestBuilder
        self.httpClient = httpClient
        self.performance = performance
        self.contextProvider = contextProvider
        self.uploadConditions = uploadConditions
        self.delay = delay
    }

    func run() {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else {
                return
            }
            
            let context = self.contextProvider.read()
            let blockers = self.uploadConditions.blockersForUpload(with: context)
            
            guard blockers.isEmpty else {
                DD.logger.debug("💡 (\(self.name)) Upload blocked: \(blockers)")
                return
            }
            
            do {
                // Upload buffer content
                let status = try self.upload(with: context)
                
                // Delete or keep batch depending on the upload status
                if status.needsRetry {
                    self.delay.increase()
                    DD.logger.debug("   → (\(self.name)) not delivered, will be retransmitted: \(status.userDebugDescription)")
                } else {
                    self.reader.flush()
                    self.delay.decrease()
                    DD.logger.debug("   → (\(self.name)) accepted, won't be retransmitted: \(status.userDebugDescription)")
                }
                
                try status.error.map { throw $0 }

            } catch BufferStreamError.noData {
                DD.logger.debug("💡 (\(self.name)) No data to upload.")
                self.delay.increase()
            } catch BufferStreamError.notEnoughData {
                DD.logger.debug("   → (\(self.name)) No enough data for an upload")
                self.delay.increase()
            } catch BufferStreamError.dataRejected {
                // Rejected, so drop the data:
                self.reader.flush()
            } catch BufferStreamError.decodingFailure(let error) {
                DD.telemetry.error("Failed to decode buffer in '\(self.name)'", error: error)
                // Error when decoding the buffer, so drop the data:
                self.reader.flush()
            } catch DataUploadError.unauthorized {
                DD.logger.error("⚠️ Make sure that the provided token still exists and you're targeting the relevant Datadog site.")
            } catch DataUploadError.httpError(let code) {
                DD.telemetry.error("Data upload finished with status code: \(code)")
            } catch DataUploadError.networkError(let error) {
                DD.telemetry.error("Data upload finished with error", error: error)
            } catch {
                // If upload can't be initiated do not retry, so drop the data:
                self.reader.flush()
                DD.telemetry.error("Failed to initiate '\(self.name)' data upload", error: error)
            }

            self.scheduleExecution()
        }

        self.work = work
        scheduleExecution()
    }

    private func scheduleExecution() {
        work.map { queue.asyncAfter(deadline: .now() + delay.current, execute: $0) }
    }

    func upload(with context: DatadogContext) throws -> DataUploadStatus {
        let request = try reader.read { try self.requestBuilder.request(stream: $0, with: context) }
        let requestID = request.value(forHTTPHeaderField: URLRequestBuilder.HTTPHeader.ddRequestIDHeaderField)

        var status: DataUploadStatus?

        let semaphore = DispatchSemaphore(value: 0)

        httpClient.send(request: request) { result in
            switch result {
            case .success(let response):
                status = DataUploadStatus(httpResponse: response, ddRequestID: requestID)
            case .failure(let error):
                status = DataUploadStatus(networkError: error)
            }

            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        return status ?? DataUploadStatus(
            needsRetry: false,
            userDebugDescription: "",
            error: nil
        )
    }
}

extension BufferUploadWorker: DataUploadWorkerType {

    func flushSynchronously() {
        // TODO: ugh!
        queue.sync {
            let context = self.contextProvider.read()
            do {
                while true {
                    let status = try self.upload(with: context)
                    try status.error.map { throw $0 }
                }
            } catch {
                self.reader.flush()
            }
        }
    }

    func cancelSynchronously() {
        queue.sync {
            // This cancellation must be performed on the `queue` to ensure that it is not called
            // in the middle of a `DispatchWorkItem` execution - otherwise, as the pending block would be
            // fully executed, it will schedule another upload by calling `nextScheduledWork(after:)` at the end.
            self.work?.cancel()
            self.work = nil
        }
    }
}
