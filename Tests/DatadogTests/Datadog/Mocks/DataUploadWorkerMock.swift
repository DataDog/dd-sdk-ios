/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest
@testable import Datadog

/// Observers the `Writer` and notifies when data was written, so `DataUploaderMock` can read it immediately.
private class WriterObserver: AsyncWriter {
    let observedWriter: ConsentAwareDataWriter
    let writeCallback: (() -> Void)

    init(_ observedWriter: ConsentAwareDataWriter, writeCallback: @escaping (() -> Void)) {
        self.observedWriter = observedWriter
        self.writeCallback = writeCallback
    }

    var queue: DispatchQueue { observedWriter.queue }

    func write<T>(value: T) where T: Encodable {
        observedWriter.write(value: value)
        queue.async { [weak self] in
            self?.writeCallback()
        }
    }

    func flushAndCancelSynchronously() {
        observedWriter.flushAndCancelSynchronously()
    }
}

class DataUploadWorkerMock: DataUploadWorkerType {
    private let queue = DispatchQueue(label: "com.datadoghq.DataUploadWorkerMock-\(UUID().uuidString)")

    private var reader: Reader?
    private var batches: [Batch] = []

    // MARK: - Observing FeatureStorage

    /// Observes the `FeatureStorage` to immediately capture written data.
    /// Returns new instance of the `FeatureStorage` which should be used instead of the original one.
    func observe(featureStorage: FeatureStorage) -> FeatureStorage {
        let originalWriter = featureStorage.writer as! ConsentAwareDataWriter
        let observedWriter = WriterObserver(originalWriter) { [weak self] in
            self?.onNextBatchWritten()
        }
        let originalReader = featureStorage.reader
        let originalArbitraryWriter = featureStorage.arbitraryAuthorizedWriter
        let originalDataOrchestrator = featureStorage.dataOrchestrator
        reader = originalReader
        return FeatureStorage(
            writer: observedWriter,
            reader: originalReader,
            arbitraryAuthorizedWriter: originalArbitraryWriter,
            dataOrchestrator: originalDataOrchestrator
        )
    }

    private func onNextBatchWritten() {
        queue.async {
            if let nextBatch = self.reader?.readNextBatch() {
                self.record(nextBatch: nextBatch)
                self.reader?.markBatchAsRead(nextBatch)
            }
        }
    }

    private func record(nextBatch: Batch) {
        queue.async {
            self.batches.append(nextBatch)
            self.waitAndReturnDataExpectation?.fulfill()
        }
    }

    // MARK: - Receiving Recorded Data

    private var waitAndReturnDataExpectation: XCTestExpectation?

    /// Waits until given number of data batches is written and returns data from these batches.
    /// Passing no `timeout` will result with picking the recommended timeout for unit tests.
    func waitAndReturnBatchedData(count: UInt, timeout: TimeInterval? = nil, file: StaticString = #file, line: UInt = #line) -> [Data] {
        precondition(waitAndReturnDataExpectation == nil, "The `DataUploadWorkerMock` is already waiting on `waitAndReturnProcessedCommands`.")

        let expectation = XCTestExpectation(description: "Receive \(count) data batches.")
        if count > 0 {
            expectation.expectedFulfillmentCount = Int(count)
        } else {
            expectation.isInverted = true
        }

        queue.sync {
            self.waitAndReturnDataExpectation = expectation
            self.batches.forEach { _ in expectation.fulfill() } // fulfill already recorded
        }

        let timeout = timeout ?? recommendedTimeoutFor(numberOfBatches: max(count, 1))
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        switch result {
        case .completed:
            break
        case .incorrectOrder, .interrupted:
            fatalError("Can't happen.")
        case .timedOut:
            XCTFail("Exceeded timeout of \(timeout)s with receiving \(batches.count) out of \(count) expected batches.", file: file, line: line)
            // Return array of dummy batches, so the crash will happen later in the test code, properly
            // printing the above error.
            return Array(repeating: .mockAny(), count: Int(count))
        case .invertedFulfillment:
            XCTFail("\(batches.count) batches were read, but not expected.", file: file, line: line)
            // Return array of dummy requests, so the crash will happen later in the test code, properly
            // printing the above error.
            return queue.sync { batches.map { $0.data } }
        @unknown default:
            fatalError()
        }

        return queue.sync { batches.map { $0.data } }
    }

    // MARK: - DataUploadWorkerType

    func flushSynchronously() {
        queue.sync {} // wait for any pending asynchronous upload
    }

    func cancelSynchronously() {
        // There is nothing to cancel. `DataUploadWorkerMock` is a passive component - it simulates
        // upload for each data written.
    }

    // MARK: - Utils

    /// Returns recommended timeout for receiving given number of batches.
    private func recommendedTimeoutFor(numberOfBatches: UInt) -> TimeInterval {
        // One batch timeout is arbitrary. It stands for the time interval from receiving the data
        // to writing it to the file. Needs to be relatively big as the CI is very slow. Higher value
        // doesn't impact the execution time of tests.
        let arbitraryTimeoutForOneBatch = 2.0
        return Double(numberOfBatches) * arbitraryTimeoutForOneBatch
    }
}
