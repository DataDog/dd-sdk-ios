/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest
@testable import Datadog

private class FileWriterObserver: FileWriterType {
    let observedWriter: FileWriter
    let writeCallback: (() -> Void)

    init(_ observedWriter: FileWriter, writeCallback: @escaping (() -> Void)) {
        self.observedWriter = observedWriter
        self.writeCallback = writeCallback
    }

    func write<T>(value: T) where T: Encodable {
        observedWriter.write(value: value)
        observedWriter.queue.async { [weak self] in
            self?.writeCallback()
        }
    }
}

class DataUploadWorkerMock: DataUploadWorkerType {
    private let queue = DispatchQueue(label: "com.datadoghq.DataUploadWorkerMock-\(UUID().uuidString)")

    private var fileReader: FileReader?
    private var batches: [Batch] = []

    // MARK: - Observing FeatureStorage

    func observe(featureStorage: FeatureStorage) -> FeatureStorage {
        let fileWriter = featureStorage.writer as! FileWriter
        let observedFileWriter = FileWriterObserver(fileWriter) { [weak self] in
            self?.readNextBatch()
        }
        fileReader = featureStorage.reader as? FileReader
        return FeatureStorage(writer: observedFileWriter, reader: featureStorage.reader)
    }

    private func readNextBatch() {
        queue.async {
            if let nextBatch = self.fileReader?.readNextBatch() {
                self.record(nextBatch: nextBatch)
                self.fileReader?.markBatchAsRead(nextBatch)
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
            // Return array of dummy batches, so the crash will happen leter in the test code, properly
            // printing the above error.
            return Array(repeating: .mockAny(), count: Int(count))
        case .invertedFulfillment:
            XCTFail("\(batches.count) batches were read, but not expected.", file: file, line: line)
            // Return array of dummy requests, so the crash will happen leter in the test code, properly
            // printing the above error.
            return queue.sync { batches.map { $0.data } }
        @unknown default:
            fatalError()
        }

        return queue.sync { batches.map { $0.data } }
    }

    // MARK: - Utils

    /// Returns recommended timeout for receiving given number of batches.
    private func recommendedTimeoutFor(numberOfBatches: UInt) -> TimeInterval {
        // One batch timeout is arbitrary. It stands for the time interval from receiving the data
        // to writting it to the file.
        let arbitraryTimeoutForOneBatch = 0.1
        return Double(numberOfBatches) * arbitraryTimeoutForOneBatch
    }
}

// MARK: - Logging feature helpers

extension DataUploadWorkerMock {
    func waitAndReturnLogMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [LogMatcher] {
        return try waitAndReturnBatchedData(count: count, file: file, line: line)
        .flatMap { batchData in
            try LogMatcher.fromArrayOfJSONObjectsData(batchData, file: file, line: line)
        }
    }
}

// MARK: - Tracing feature helpers

extension DataUploadWorkerMock {
    func waitAndReturnSpanMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [SpanMatcher] {
        return try waitAndReturnBatchedData(count: count, file: file, line: line)
        .flatMap { batchData in
            try SpanMatcher.fromNewlineSeparatedJSONObjectsData(batchData)
        }
    }
}
