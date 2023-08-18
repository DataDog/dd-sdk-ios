/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class DataUploadWorkerTests: XCTestCase {
    private let uploaderQueue = DispatchQueue(label: "dd-tests-uploader", target: .global(qos: .utility))

    lazy var dateProvider = RelativeDateProvider(advancingBySeconds: 1)
    lazy var orchestrator = FilesOrchestrator(
        directory: .init(url: temporaryDirectory),
        performance: StoragePerformanceMock.writeEachObjectToNewFileAndReadAllFiles,
        dateProvider: dateProvider
    )
    lazy var writer = FileWriter(
        orchestrator: orchestrator,
        encryption: nil,
        forceNewFile: false
    )
    lazy var reader = FileReader(
        orchestrator: orchestrator,
        encryption: nil
    )

    override func setUp() {
        super.setUp()
        CreateTemporaryDirectory()
    }

    override func tearDown() {
        DeleteTemporaryDirectory()
        super.tearDown()
    }

    // MARK: - Data Uploads

    func testItUploadsAllData() {
        let uploadExpectation = self.expectation(description: "Make 3 uploads")
        uploadExpectation.expectedFulfillmentCount = 3

        let dataUploader = DataUploaderMock(
            uploadStatus: DataUploadStatus(httpResponse: .mockResponseWith(statusCode: 200), ddRequestID: nil),
            onUpload: uploadExpectation.fulfill
        )

        // Given
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])

        // When
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny()
        )

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(dataUploader.uploadedEvents[0], Event(data: #"{"k1":"v1"}"#.utf8Data))
        XCTAssertEqual(dataUploader.uploadedEvents[1], Event(data: #"{"k2":"v2"}"#.utf8Data))
        XCTAssertEqual(dataUploader.uploadedEvents[2], Event(data: #"{"k3":"v3"}"#.utf8Data))

        worker.cancelSynchronously()
        XCTAssertEqual(try orchestrator.directory.files().count, 0)
    }

    func testGivenDataToUpload_whenUploadFinishesAndDoesNotNeedToBeRetried_thenDataIsDeleted() {
        let startUploadExpectation = self.expectation(description: "Upload has started")

        let mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: false))
        mockDataUploader.onUpload = { startUploadExpectation.fulfill() }

        // Given
        writer.write(value: ["key": "value"])
        XCTAssertEqual(try orchestrator.directory.files().count, 1)

        // When
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: .mockAny()
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(try orchestrator.directory.files().count, 0, "When upload finishes with `needsRetry: false`, data should be deleted")
    }

    func testGivenDataToUpload_whenUploadFailsToBeInitiated_thenDataIsDeleted() {
        let initiatingUploadExpectation = self.expectation(description: "Upload is being initiated")

        let mockDataUploader = DataUploaderMock(uploadStatus: .mockRandom())
        mockDataUploader.onUpload = {
            initiatingUploadExpectation.fulfill()
            throw ErrorMock("Failed to prepare upload")
        }

        // Given
        writer.write(value: ["key": "value"])
        XCTAssertEqual(try orchestrator.directory.files().count, 1)

        // When
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: .mockAny()
        )

        wait(for: [initiatingUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(try orchestrator.directory.files().count, 0, "When upload fails to be initiated, data should be deleted")
    }

    func testGivenDataToUpload_whenUploadFinishesAndNeedsToBeRetried_thenDataIsPreserved() {
        let startUploadExpectation = self.expectation(description: "Upload has started")

        let mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: true))
        mockDataUploader.onUpload = { startUploadExpectation.fulfill() }

        // Given
        writer.write(value: ["key": "value"])
        XCTAssertEqual(try orchestrator.directory.files().count, 1)

        // When
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: .mockAny()
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(try orchestrator.directory.files().count, 1, "When upload finishes with `needsRetry: true`, data should be preserved")
    }

    // MARK: - Upload Interval Changes

    func testWhenThereIsNoBatch_thenIntervalIncreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is increased")
        let mockDelay = MockDelay { command in
            if case .increase = command {
                delayChangeExpectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }

        // When
        XCTAssertEqual(try orchestrator.directory.files().count, 0)

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let httpClient = URLSessionClient(session: server.getInterceptedURLSession())

        let dataUploader = DataUploader(
            httpClient: httpClient,
            requestBuilder: FeatureRequestBuilderMock()
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.neverUpload(),
            delay: mockDelay,
            featureName: .mockAny()
        )

        // Then
        server.waitFor(requestsCompletion: 0)
        waitForExpectations(timeout: 1, handler: nil)
        worker.cancelSynchronously()
    }

    func testWhenBatchFails_thenIntervalIncreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is increased")
        let mockDelay = MockDelay { command in
            if case .increase = command {
                delayChangeExpectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }

        // When
        writer.write(value: ["k1": "v1"])

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 500)))
        let httpClient = URLSessionClient(session: server.getInterceptedURLSession())

        let dataUploader = DataUploader(
            httpClient: httpClient,
            requestBuilder: FeatureRequestBuilderMock()
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: mockDelay,
            featureName: .mockAny()
        )

        // Then
        server.waitFor(requestsCompletion: 1)
        waitForExpectations(timeout: 1, handler: nil)
        worker.cancelSynchronously()
    }

    func testWhenBatchSucceeds_thenIntervalDecreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is decreased")
        let mockDelay = MockDelay { command in
            if case .decrease = command {
                delayChangeExpectation.fulfill()
            } else {
                XCTFail("Wrong command is sent!")
            }
        }

        // When
        writer.write(value: ["k1": "v1"])

        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let httpClient = URLSessionClient(session: server.getInterceptedURLSession())

        let dataUploader = DataUploader(
            httpClient: httpClient,
            requestBuilder: FeatureRequestBuilderMock()
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: mockDelay,
            featureName: .mockAny()
        )

        // Then
        server.waitFor(requestsCompletion: 1)
        waitForExpectations(timeout: 2, handler: nil)
        worker.cancelSynchronously()
    }

    // MARK: - Notifying Upload Progress

    func testWhenDataIsBeingUploaded_itPrintsUploadProgressInformation() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        writer.write(value: ["key": "value"])

        let randomUploadStatus: DataUploadStatus = .mockRandom()
        let randomFeatureName: String = .mockRandom()

        // When
        let startUploadExpectation = self.expectation(description: "Upload has started")
        let mockDataUploader = DataUploaderMock(uploadStatus: randomUploadStatus)
        mockDataUploader.onUpload = { startUploadExpectation.fulfill() }

        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: randomFeatureName
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        let expectedSummary = randomUploadStatus.needsRetry ? "not delivered, will be retransmitted" : "accepted, won't be retransmitted"
        XCTAssertEqual(dd.logger.debugLogs.count, 2)

        XCTAssertEqual(
            dd.logger.debugLogs[0].message,
            "⏳ (\(randomFeatureName)) Uploading batch...",
            "Batch start information should be printed to `userLogger`. All captured logs:\n\(dd.logger.recordedLogs)"
        )

        XCTAssertEqual(
            dd.logger.debugLogs[1].message,
            "   → (\(randomFeatureName)) \(expectedSummary): \(randomUploadStatus.userDebugDescription)",
            "Batch completion information should be printed to `userLogger`. All captured logs:\n\(dd.logger.recordedLogs)"
        )
    }

    func testWhenDataIsUploadedWithUnauthorizedError_itPrintsUnauthoriseMessage_toUserLogger() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        writer.write(value: ["key": "value"])

        let randomUploadStatus: DataUploadStatus = .mockWith(error: .unauthorized)

        // When
        let startUploadExpectation = self.expectation(description: "Upload has started")
        let mockDataUploader = DataUploaderMock(uploadStatus: randomUploadStatus)
        mockDataUploader.onUpload = { startUploadExpectation.fulfill() }

        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: .mockRandom()
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(
            dd.logger.errorLog?.message,
            "⚠️ Make sure that the provided token still exists and you're targeting the relevant Datadog site.",
            "An error should be printed to `userLogger`. All captured logs:\n\(dd.logger.recordedLogs)"
        )
    }

    func testWhenDataIsUploadedWith500StatusCode_itSendsErrorTelemetry() {
        // Given
        let dd = DD.mockWith(telemetry: TelemetryMock())
        defer { dd.reset() }

        writer.write(value: ["key": "value"])
        let randomUploadStatus: DataUploadStatus = .mockWith(error: .httpError(statusCode: 500))

        // When
        let startUploadExpectation = self.expectation(description: "Upload has started")
        let mockDataUploader = DataUploaderMock(uploadStatus: randomUploadStatus)
        mockDataUploader.onUpload = { startUploadExpectation.fulfill() }

        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: .mockRandom()
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(dd.telemetry.messages.count, 1)

        guard case .error(_, let message, _, _) = dd.telemetry.messages.first else {
            return XCTFail("An error should be send to `DD.telemetry`.")
        }

        XCTAssertEqual(message,"Data upload finished with status code: 500")
    }

    func testWhenDataCannotBeUploadedDueToNetworkError_itSendsErrorTelemetry() {
        // Given
        let dd = DD.mockWith(telemetry: TelemetryMock())
        defer { dd.reset() }

        writer.write(value: ["key": "value"])
        let randomUploadStatus: DataUploadStatus = .mockWith(error: .networkError(error: .mockAny()))

        // When
        let startUploadExpectation = self.expectation(description: "Upload has started")
        let mockDataUploader = DataUploaderMock(uploadStatus: randomUploadStatus)
        mockDataUploader.onUpload = { startUploadExpectation.fulfill() }

        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: .mockRandom()
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(dd.telemetry.messages.count, 1)

        guard case .error(_, let message, _, _) = dd.telemetry.messages.first else {
            return XCTFail("An error should be send to `DD.telemetry`.")
        }

        XCTAssertEqual(message,#"Data upload finished with error - Error Domain=abc Code=0 "(null)""#)
    }

    func testWhenDataCannotBePreparedForUpload_itSendsErrorTelemetry() {
        // Given
        let dd = DD.mockWith(telemetry: TelemetryMock())
        defer { dd.reset() }

        writer.write(value: ["key": "value"])

        // When
        let initiatingUploadExpectation = self.expectation(description: "Upload is being initiated")
        let mockDataUploader = DataUploaderMock(uploadStatus: .mockRandom())
        mockDataUploader.onUpload = {
            initiatingUploadExpectation.fulfill()
            throw ErrorMock("Failed to prepare upload")
        }

        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: "some-feature"
        )

        wait(for: [initiatingUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(dd.telemetry.messages.count, 1)

        guard case .error(_, let message, _, _) = dd.telemetry.messages.first else {
            return XCTFail("An error should be send to `DD.telemetry`.")
        }

        XCTAssertEqual(message, #"Failed to initiate 'some-feature' data upload - Failed to prepare upload"#)
    }

    // MARK: - Tearing Down

    func testWhenCancelled_itPerformsNoMoreUploads() {
        // Given
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let httpClient = URLSessionClient(session: server.getInterceptedURLSession())

        let dataUploader = DataUploader(
            httpClient: httpClient,
            requestBuilder: FeatureRequestBuilderMock()
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.neverUpload(),
            delay: MockDelay(),
            featureName: .mockAny()
        )

        // When
        worker.cancelSynchronously()

        // Then
        writer.write(value: ["k1": "v1"])

        server.waitFor(requestsCompletion: 0)
    }

    func testItFlushesAllData() {
        let uploadExpectation = self.expectation(description: "Make 3 uploads")
        uploadExpectation.expectedFulfillmentCount = 3

        let dataUploader = DataUploaderMock(
            uploadStatus: .mockRandom(),
            onUpload: uploadExpectation.fulfill
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny()
        )

        // Given
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])

        // When
        worker.flushSynchronously()

        // Then
        XCTAssertEqual(try orchestrator.directory.files().count, 0)

        waitForExpectations(timeout: 1)
        XCTAssertEqual(dataUploader.uploadedEvents[0], Event(data: #"{"k1":"v1"}"#.utf8Data))
        XCTAssertEqual(dataUploader.uploadedEvents[1], Event(data: #"{"k2":"v2"}"#.utf8Data))
        XCTAssertEqual(dataUploader.uploadedEvents[2], Event(data: #"{"k3":"v3"}"#.utf8Data))

        worker.cancelSynchronously()
    }
}

struct MockDelay: Delay {
    enum Command {
        case increase, decrease
    }

    var callback: ((Command) -> Void)?
    let current: TimeInterval = 0.1

    mutating func decrease() {
        callback?(.decrease)
        callback = nil
    }
    mutating func increase() {
        callback?(.increase)
        callback = nil
    }
}

private extension DataUploadConditions {
    static func alwaysUpload() -> DataUploadConditions {
        return DataUploadConditions(minBatteryLevel: 0)
    }

    static func neverUpload() -> DataUploadConditions {
        return DataUploadConditions(minBatteryLevel: 1)
    }
}
