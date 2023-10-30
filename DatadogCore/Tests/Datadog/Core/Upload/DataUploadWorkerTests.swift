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
        dateProvider: dateProvider,
        telemetry: NOPTelemetry()
    )
    lazy var writer = FileWriter(
        orchestrator: orchestrator,
        forceNewFile: false,
        encryption: nil,
        telemetry: NOPTelemetry()
    )
    lazy var reader = FileReader(
        orchestrator: orchestrator,
        encryption: nil,
        telemetry: NOPTelemetry()
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
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: 1
        )

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(dataUploader.uploadedEvents[0], Event(data: #"{"k1":"v1"}"#.utf8Data))
        XCTAssertEqual(dataUploader.uploadedEvents[1], Event(data: #"{"k2":"v2"}"#.utf8Data))
        XCTAssertEqual(dataUploader.uploadedEvents[2], Event(data: #"{"k3":"v3"}"#.utf8Data))

        worker.cancelSynchronously()
        XCTAssertEqual(try orchestrator.directory.files().count, 0)
    }

    func testItUploadsAllDataSequentiallyWithMaxBatchesPerUploadWithoutDelay() {
        let uploadExpectation = self.expectation(description: "Make 2 uploads")
        uploadExpectation.expectedFulfillmentCount = 2

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
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: 2
        )

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(dataUploader.uploadedEvents.count, 2)
        XCTAssertEqual(dataUploader.uploadedEvents[0], Event(data: #"{"k1":"v1"}"#.utf8Data))
        XCTAssertEqual(dataUploader.uploadedEvents[1], Event(data: #"{"k2":"v2"}"#.utf8Data))

        worker.cancelSynchronously()
        XCTAssertEqual(try orchestrator.directory.files().count, 1)
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
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
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
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
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
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(try orchestrator.directory.files().count, 1, "When upload finishes with `needsRetry: true`, data should be preserved")
    }

    // MARK: - Upload Interval Changes

    func testWhenThereIsNoBatch_thenIntervalIncreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is increased")
        let initialUploadDelay = 0.01
        let delay = DataUploadDelay(
            performance: UploadPerformanceMock(
                initialUploadDelay: initialUploadDelay,
                minUploadDelay: 0,
                maxUploadDelay: 1,
                uploadDelayChangeRate: 0.01
            )
        )

        // When
        XCTAssertEqual(try orchestrator.directory.files().count, 0)

        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: DataUploaderMock(uploadStatus: .mockWith()),
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.neverUpload(),
            delay: delay,
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        // Then
        wait(until: { [uploaderQueue] in
            uploaderQueue.sync {
                delay.current > initialUploadDelay
            }
        }, andThenFulfill: delayChangeExpectation)
        wait(for: [delayChangeExpectation], timeout: 0.5)
        worker.cancelSynchronously()
    }

    func testWhenBatchFails_thenIntervalIncreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is increased")
        let initialUploadDelay = 0.01
        let delay = DataUploadDelay(
            performance: UploadPerformanceMock(
                initialUploadDelay: initialUploadDelay,
                minUploadDelay: 0,
                maxUploadDelay: 1,
                uploadDelayChangeRate: 0.01
            )
        )

        // When
        writer.write(value: ["k1": "v1"])

        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: DataUploaderMock(uploadStatus: .mockWith(needsRetry: true)),
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: delay,
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        // Then
        wait(until: { [uploaderQueue] in
            uploaderQueue.sync {
                delay.current > initialUploadDelay
            }
        }, andThenFulfill: delayChangeExpectation)
        wait(for: [delayChangeExpectation], timeout: 0.5)
        worker.cancelSynchronously()
    }

    func testWhenBatchSucceeds_thenIntervalDecreases() {
        let delayChangeExpectation = expectation(description: "Upload delay is decreased")
        let initialUploadDelay = 0.05
        let delay = DataUploadDelay(
            performance: UploadPerformanceMock(
                initialUploadDelay: initialUploadDelay,
                minUploadDelay: 0,
                maxUploadDelay: 1,
                uploadDelayChangeRate: 0.01
            )
        )
        // When
        writer.write(value: ["k1": "v1"])

        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: DataUploaderMock(uploadStatus: .mockWith(needsRetry: false)),
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: delay,
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        // Then
        wait(until: { [uploaderQueue] in
            uploaderQueue.sync {
                delay.current < initialUploadDelay
            }
        }, andThenFulfill: delayChangeExpectation)
        wait(for: [delayChangeExpectation], timeout: 0.5)
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
            featureName: randomFeatureName,
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
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
            featureName: .mockRandom(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
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

    func testWhenDataIsUploadedWith500StatusCode_itSendsErrorTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()

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
            featureName: .mockRandom(),
            telemetry: telemetry,
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)

        let error = try XCTUnwrap(telemetry.messages.first?.asError, "An error should be send to `telemetry`.")
        XCTAssertEqual(error.message,"Data upload finished with status code: 500")
    }

    func testWhenDataCannotBeUploadedDueToNetworkError_itSendsErrorTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()

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
            featureName: .mockRandom(),
            telemetry: telemetry,
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)

        let error = try XCTUnwrap(telemetry.messages.first?.asError, "An error should be send to `telemetry`.")
        XCTAssertEqual(error.message, #"Data upload finished with error - Error Domain=abc Code=0 "(null)""#)
    }

    func testWhenDataCannotBePreparedForUpload_itSendsErrorTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()

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
            featureName: "some-feature",
            telemetry: telemetry,
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        wait(for: [initiatingUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)

        let error = try XCTUnwrap(telemetry.messages.first?.asError, "An error should be send to `telemetry`.")
        XCTAssertEqual(error.message, #"Failed to initiate 'some-feature' data upload - Failed to prepare upload"#)
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
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
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
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
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

    func testItTriggersBackgroundTaskBeginEndForSuccessfulUpload() {
        let expectTaskRegistered = expectation(description: "task should be registered")
        let expectTaskEnded = expectation(description: "task should be ended")
        let backgroundTaskCoordinator = SpyBackgroundTaskCoordinator(
            beginBackgroundTaskCalled: {
                expectTaskRegistered.fulfill()
            }, endBackgroundTaskCalled: {
                expectTaskEnded.fulfill()
            }
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: DataUploaderMock(uploadStatus: .mockWith()),
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTaskCoordinator: backgroundTaskCoordinator
        )
        writer.write(value: ["k1": "v1"])

        // Then
        withExtendedLifetime(worker) {
            wait(for: [expectTaskRegistered, expectTaskEnded], timeout: 0.5)
        }
    }

    func testItTriggersBackgroundTaskBeginEndWhenBlockerOccurs() {
        let expectTaskRegistered = expectation(description: "task should be registered")
        let expectTaskEnded = expectation(description: "task should be ended")
        let backgroundTaskCoordinator = SpyBackgroundTaskCoordinator(
            beginBackgroundTaskCalled: {
                expectTaskRegistered.fulfill()
            }, endBackgroundTaskCalled: {
                expectTaskEnded.fulfill()
            }
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: DataUploaderMock(uploadStatus: .mockWith()),
            contextProvider: .mockAny(),
            uploadConditions: .neverUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTaskCoordinator: backgroundTaskCoordinator
        )
        writer.write(value: ["k1": "v1"])

        // Then
        withExtendedLifetime(worker) {
            wait(for: [expectTaskRegistered, expectTaskEnded], timeout: 0.5)
        }
    }

    func testItTriggersBackgroundTaskEndWhenThereIsNothingToUpload() {
        let expectTaskEnded = expectation(description: "task should be ended")
        let backgroundTaskCoordinator = SpyBackgroundTaskCoordinator(
            beginBackgroundTaskCalled: {
                XCTFail("begin background task should not be called")
            }, endBackgroundTaskCalled: {
                expectTaskEnded.fulfill()
            }
        )
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: DataUploaderMock(uploadStatus: .mockWith()),
            contextProvider: .mockAny(),
            uploadConditions: .neverUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTaskCoordinator: backgroundTaskCoordinator
        )
        // Then
        withExtendedLifetime(worker) {
            wait(for: [expectTaskEnded], timeout: 0.5)
        }
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

private class SpyBackgroundTaskCoordinator: BackgroundTaskCoordinator {
    private let beginBackgroundTaskCalled: () -> Void
    private let endBackgroundTaskCalled: () -> Void

    init(
        beginBackgroundTaskCalled: @escaping () -> Void,
        endBackgroundTaskCalled: @escaping () -> Void
    ) {
        self.beginBackgroundTaskCalled = beginBackgroundTaskCalled
        self.endBackgroundTaskCalled = endBackgroundTaskCalled
    }

    func beginBackgroundTask() {
        beginBackgroundTaskCalled()
    }

    func endBackgroundTask() {
        endBackgroundTaskCalled()
    }
}
