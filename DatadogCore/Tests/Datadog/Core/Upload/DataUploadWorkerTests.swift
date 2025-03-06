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

    func testItUploadsAllData() throws {
        let uploadExpectation = self.expectation(description: "Make 3 uploads")
        uploadExpectation.expectedFulfillmentCount = 3

        let telemetry = TelemetryMock()

        let dataUploader = DataUploaderMock(
            uploadStatus: DataUploadStatus(
                httpResponse: .mockResponseWith(statusCode: 200),
                ddRequestID: nil,
                attempt: 0
            ),
            onUpload: { previousUploadStatus in
                XCTAssertNil(previousUploadStatus)
                uploadExpectation.fulfill()
            }
        )

        // Given
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])

        // When
        let featureName: String = .mockAny()
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny(),
            telemetry: telemetry,
            maxBatchesPerUpload: 1
        )

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(dataUploader.uploadedEvents[0], Event(data: #"{"k1":"v1"}"#.utf8Data))
        XCTAssertEqual(dataUploader.uploadedEvents[1], Event(data: #"{"k2":"v2"}"#.utf8Data))
        XCTAssertEqual(dataUploader.uploadedEvents[2], Event(data: #"{"k3":"v3"}"#.utf8Data))

        worker.cancelSynchronously()
        XCTAssertEqual(try orchestrator.directory.files().count, 0)

        XCTAssertEqual(telemetry.messages.count, 3)
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "upload_quality"), "An upload quality metric should be send to `telemetry`.")
        XCTAssertEqual(metric.attributes["track"] as? String, featureName)
        XCTAssertNil(metric.attributes["failure"])
        XCTAssertNil(metric.attributes["blockers"])
    }

    func testItUploadsDataSequentiallyWithoutDelay_whenMaxBatchesPerUploadIsSet() throws {
        let uploadExpectation = self.expectation(description: "Make 2 uploads")
        uploadExpectation.expectedFulfillmentCount = 2

        let telemetry = TelemetryMock()

        let dataUploader = DataUploaderMock(
            uploadStatus: DataUploadStatus(
                httpResponse: .mockResponseWith(statusCode: 200),
                ddRequestID: nil,
                attempt: 0
            ),
            onUpload: { previousUploadStatus in
                XCTAssertNil(previousUploadStatus)
                uploadExpectation.fulfill()
            }
        )

        // Given
        writer.write(value: ["k1": "v1"])
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])

        // When
        let featureName: String = .mockAny()
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: featureName,
            telemetry: telemetry,
            maxBatchesPerUpload: 2
        )

        // Then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(dataUploader.uploadedEvents.count, 2)
        XCTAssertEqual(dataUploader.uploadedEvents[0], Event(data: #"{"k1":"v1"}"#.utf8Data))
        XCTAssertEqual(dataUploader.uploadedEvents[1], Event(data: #"{"k2":"v2"}"#.utf8Data))

        worker.cancelSynchronously()
        XCTAssertEqual(try orchestrator.directory.files().count, 1)

        XCTAssertEqual(telemetry.messages.count, 2)
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "upload_quality"), "An upload quality metric should be send to `telemetry`.")
        XCTAssertEqual(metric.attributes["track"] as? String, featureName)
        XCTAssertNil(metric.attributes["failure"])
        XCTAssertNil(metric.attributes["blockers"])
    }

    func testGivenDataToUpload_whenUploadFinishesAndDoesNotNeedToBeRetried_thenDataIsDeleted() {
        let startUploadExpectation = self.expectation(description: "Upload has started")

        let mockDataUploader = DataUploaderMock(uploadStatus: .mockWith(needsRetry: false))
        mockDataUploader.onUpload = { previousUploadStatus in
            XCTAssertNil(previousUploadStatus)
            startUploadExpectation.fulfill()
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

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(try orchestrator.directory.files().count, 0, "When upload finishes with `needsRetry: false`, data should be deleted")
    }

    func testGivenDataToUpload_whenUploadFailsToBeInitiated_thenDataIsDeleted() {
        let initiatingUploadExpectation = self.expectation(description: "Upload is being initiated")

        let mockDataUploader = DataUploaderMock(uploadStatus: .mockRandom())
        mockDataUploader.onUpload = { previousUploadStatus in
            XCTAssertNil(previousUploadStatus)
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
        mockDataUploader.onUpload = { previousUploadStatus in
            XCTAssertNil(previousUploadStatus)
            startUploadExpectation.fulfill()
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

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(try orchestrator.directory.files().count, 1, "When upload finishes with `needsRetry: true`, data should be preserved")
    }

    func testGivenDataToUpload_whenUploadFinishesAndNeedsToBeRetried_thenPreviousUploadStatusIsNotNil() {
        let startUploadExpectation = self.expectation(description: "Upload has started")
        startUploadExpectation.expectedFulfillmentCount = 3

        let mockDataUploader = DataUploaderMock(
            uploadStatuses: [
                .mockWith(needsRetry: true, attempt: 0),
                .mockWith(needsRetry: true, attempt: 1),
                .mockWith(needsRetry: false, attempt: 2)
            ]
        )

        var attempt: UInt = 0
        mockDataUploader.onUpload = { previousUploadStatus in
            if attempt == 0 {
                XCTAssertNil(previousUploadStatus)
            } else {
                XCTAssertNotNil(previousUploadStatus)
                XCTAssertEqual(previousUploadStatus?.attempt, attempt - 1)
            }

            attempt += 1
            startUploadExpectation.fulfill()
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
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuick),
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        wait(for: [startUploadExpectation], timeout: 5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(try orchestrator.directory.files().count, 0)
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
            uploadConditions: .neverUpload(),
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

    func testWhenBatchFails_thenIntervalIncreasesAndUploadCycleEnds() {
        let delayChangeExpectation = expectation(description: "Upload delay is increased")
        delayChangeExpectation.expectedFulfillmentCount = 1

        let uploadAttemptExpectation = expectation(description: "Upload was attempted")
        uploadAttemptExpectation.expectedFulfillmentCount = 1

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
        writer.write(value: ["k2": "v2"])
        writer.write(value: ["k3": "v3"])

        let dataUploader = DataUploaderMock(
            uploadStatus: .mockWith(
                needsRetry: true,
                error: .httpError(statusCode: .internalServerError)
            )
        ) { previousUploadStatus in
            XCTAssertNil(previousUploadStatus)
            uploadAttemptExpectation.fulfill()
        }

        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
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
        wait(for: [delayChangeExpectation, uploadAttemptExpectation], timeout: 0.5)
        worker.cancelSynchronously()
    }

    func testWhenBatchSucceeds_thenIntervalResets() {
        let startUploadExpectation = expectation(description: "Upload started")
        let minUploadDelay: Double = .mockRandom(min: 1, max: 2)
        let delay = DataUploadDelay(
            performance: UploadPerformanceMock(
                initialUploadDelay: 0.05,
                minUploadDelay: minUploadDelay,
                maxUploadDelay: 2,
                uploadDelayChangeRate: 0.01
            )
        )

        let dataUploader = DataUploaderMock(uploadStatus: .mockWith(responseCode: 202)) { status in
            XCTAssertNil(status)
            startUploadExpectation.fulfill()
        }

        // When
        // Given
        writer.write(value: ["k1": "v1"])

        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: dataUploader,
            contextProvider: .mockAny(),
            uploadConditions: DataUploadConditions.alwaysUpload(),
            delay: delay,
            featureName: .mockAny(),
            telemetry: NOPTelemetry(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        // Then
        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        XCTAssertEqual(delay.current, minUploadDelay)
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
        mockDataUploader.onUpload = { previousUploadStatus in
            XCTAssertNil(previousUploadStatus)
            startUploadExpectation.fulfill()
        }

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
            "⏳ (\(randomFeatureName)) Uploading batches...",
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

        let randomUploadStatus: DataUploadStatus = .mockWith(
            error: .httpError(
                statusCode: [.unauthorized, .forbidden].randomElement()!
            )
        )

        // When
        let startUploadExpectation = self.expectation(description: "Upload has started")
        let mockDataUploader = DataUploaderMock(uploadStatus: randomUploadStatus)
        mockDataUploader.onUpload = { previousUploadStatus in
            XCTAssertNil(previousUploadStatus)
            startUploadExpectation.fulfill()
        }

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

    func testWhenUploadIsBlocked_itDoesSendUploadQualityTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()

        // When
        let uploadExpectation = self.expectation(description: "Upload has started")
        uploadExpectation.isInverted = true

        let mockDataUploader = DataUploaderMock(uploadStatus: .mockRandom()) { _ in
            uploadExpectation.fulfill()
        }

        let featureName: String = .mockRandom()
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockWith(
                context: .mockWith(
                    networkConnectionInfo: .mockWith(
                        reachability: .no
                    ),
                    batteryStatus: .mockWith(
                        state: .unplugged,
                        level: 0.05
                    )
                )
            ),
            uploadConditions: .neverUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: featureName,
            telemetry: telemetry,
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        wait(for: [uploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "upload_quality"), "An upload quality metric should be send to `telemetry`.")
        XCTAssertEqual(metric.attributes["failure"] as? String, "blocker")
        XCTAssertEqual(metric.attributes["blockers"] as? [String], ["offline", "low_battery"])
        XCTAssertEqual(metric.attributes["track"] as? String, featureName)
    }

    func testWhenDataIsUploadedWithServerError_itDoesNotSendErrorTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()

        writer.write(value: ["key": "value"])
        let randomStatusCode: HTTPResponseStatusCode = [
            .internalServerError,
            .serviceUnavailable,
            .badGateway,
            .gatewayTimeout,
            .insufficientStorage
        ].randomElement()!

        // When
        let startUploadExpectation = self.expectation(description: "Upload has started")
        let mockDataUploader = DataUploaderMock(
            uploadStatus: .mockWith(error: .httpError(statusCode: randomStatusCode))
        )

        mockDataUploader.onUpload = { previousUploadStatus in
            XCTAssertNil(previousUploadStatus)
            startUploadExpectation.fulfill()
        }

        let featureName: String = .mockRandom()
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: featureName,
            telemetry: telemetry,
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "upload_quality"), "An upload quality metric should be send to `telemetry`.")
        XCTAssertEqual(metric.attributes["failure"] as? String, "\(randomStatusCode)")
        XCTAssertEqual(metric.attributes["track"] as? String, featureName)
    }

    func testWhenDataIsUploadedWithAlertingStatusCode_itSendsErrorTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()

        writer.write(value: ["key": "value"])
        let randomStatusCode: HTTPResponseStatusCode = [
            .badRequest,
            .requestTimeout,
            .payloadTooLarge,
            .tooManyRequests,
            .unexpected,
        ].randomElement()!

        // When
        let startUploadExpectation = self.expectation(description: "Upload has started")
        let mockDataUploader = DataUploaderMock(
            uploadStatus: .mockWith(error: .httpError(statusCode: randomStatusCode))
        )

        mockDataUploader.onUpload = { previousUploadStatus in
            XCTAssertNil(previousUploadStatus)
            startUploadExpectation.fulfill()
        }

        let featureName: String = .mockRandom()
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: featureName,
            telemetry: telemetry,
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(telemetry.messages.count, 2)

        let error = try XCTUnwrap(telemetry.messages.firstError(), "An error should be send to `telemetry`.")
        XCTAssertEqual(error.message,"Data upload finished with status code: \(randomStatusCode.rawValue)")

        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "upload_quality"), "An upload quality metric should be send to `telemetry`.")
        XCTAssertEqual(metric.attributes["failure"] as? String, "\(randomStatusCode)")
        XCTAssertEqual(metric.attributes["track"] as? String, featureName)
    }

    func testWhenDataCannotBeUploadedDueToNetworkError_itSendsErrorTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()

        writer.write(value: ["key": "value"])

        let nserror: NSError = .mockAny()

        // When
        let startUploadExpectation = self.expectation(description: "Upload has started")
        let mockDataUploader = DataUploaderMock(
            uploadStatus: .mockWith(error: .networkError(error: nserror))
        )
        mockDataUploader.onUpload = { previousUploadStatus in
            XCTAssertNil(previousUploadStatus)
            startUploadExpectation.fulfill()
        }

        let featureName: String = .mockRandom()
        let worker = DataUploadWorker(
            queue: uploaderQueue,
            fileReader: reader,
            dataUploader: mockDataUploader,
            contextProvider: .mockAny(),
            uploadConditions: .alwaysUpload(),
            delay: DataUploadDelay(performance: UploadPerformanceMock.veryQuickInitialUpload),
            featureName: featureName,
            telemetry: telemetry,
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100)
        )

        wait(for: [startUploadExpectation], timeout: 0.5)
        worker.cancelSynchronously()

        // Then
        XCTAssertEqual(telemetry.messages.count, 2)

        let error = try XCTUnwrap(telemetry.messages.firstError(), "An error should be send to `telemetry`.")
        XCTAssertEqual(error.message, #"Data upload finished with error - Error Domain=abc Code=0 "(null)""#)

        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "upload_quality"), "An upload quality metric should be send to `telemetry`.")
        XCTAssertEqual(metric.attributes["failure"] as? String, "\(nserror.code)")
        XCTAssertEqual(metric.attributes["track"] as? String, featureName)
    }

    func testWhenDataCannotBePreparedForUpload_itSendsErrorTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()

        writer.write(value: ["key": "value"])

        // When
        let initiatingUploadExpectation = self.expectation(description: "Upload is being initiated")
        let mockDataUploader = DataUploaderMock(uploadStatus: .mockRandom())
        mockDataUploader.onUpload = { previousUploadStatus in
            XCTAssertNil(previousUploadStatus)
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
        XCTAssertEqual(telemetry.messages.count, 2)

        let error = try XCTUnwrap(telemetry.messages.firstError(), "An error should be send to `telemetry`.")
        XCTAssertEqual(error.message, #"Failed to initiate 'some-feature' data upload - Failed to prepare upload"#)

        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "upload_quality"), "An upload quality metric should be send to `telemetry`.")
        XCTAssertEqual(metric.attributes["failure"] as? String, "invalid")
        XCTAssertEqual(metric.attributes["track"] as? String, "some-feature")
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
            uploadConditions: .neverUpload(),
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
            uploadStatus: .mockWith(needsRetry: false),
            onUpload: { previousUploadStatus in
                XCTAssertNil(previousUploadStatus)
                uploadExpectation.fulfill()
            }
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

        // Given
        writer.write(value: ["k1": "v1"])

        // When
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

        // Given
        writer.write(value: ["k1": "v1"])

        // When
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
