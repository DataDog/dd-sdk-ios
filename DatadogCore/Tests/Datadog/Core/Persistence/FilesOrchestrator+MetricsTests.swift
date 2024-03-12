/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class FilesOrchestrator_MetricsTests: XCTestCase {
    private let telemetry = TelemetryMock()
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private var storage: StoragePerformanceMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var upload: UploadPerformanceMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        CreateTemporaryDirectory()

        let performance: PerformancePreset = .mockRandom()
        storage = StoragePerformanceMock(other: performance)
        upload = UploadPerformanceMock(other: performance)
    }

    override func tearDown() {
        DeleteTemporaryDirectory()
        super.tearDown()
    }

    private func createOrchestrator() -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: Directory(url: temporaryDirectory),
            performance: PerformancePreset.combining(storagePerformance: storage, uploadPerformance: upload),
            dateProvider: dateProvider,
            telemetry: telemetry,
            metricsData: FilesOrchestrator.MetricsData(
                trackName: "track name",
                consentLabel: "consent value",
                uploaderPerformance: upload
            )
        )
    }

    // MARK: - "Batch Deleted" Metric

    func testWhenReadableFileIsDeleted_itSendsBatchDeletedMetric() throws {
        // Given
        let orchestrator = createOrchestrator()
        let file = try XCTUnwrap(orchestrator.getWritableFile(writeSize: 1) as? ReadableFile)
        let expectedBatchAge = storage.minFileAgeForRead + 1

        // When:
        // - wait and delete the file
        dateProvider.advance(bySeconds: expectedBatchAge)
        orchestrator.delete(readableFile: file, deletionReason: .intakeCode(responseCode: 202))

        // Then
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "Batch Deleted"))
        DDAssertReflectionEqual(metric.attributes, [
            "metric_type": "batch deleted",
            "track": "track name",
            "consent": "consent value",
            "uploader_delay": [
                "min": upload.minUploadDelay.toMilliseconds,
                "max": upload.maxUploadDelay.toMilliseconds
            ],
            "uploader_window": storage.uploaderWindow.toMilliseconds,
            "in_background": false,
            "batch_age": expectedBatchAge.toMilliseconds,
            "batch_removal_reason": "intake-code-202",
        ])
    }

    func testWhenObsoleteFileIsDeleted_itSendsBatchDeletedMetric() throws {
        // Given:
        // - request some batch to be created
        let orchestrator = createOrchestrator()
        _ = try orchestrator.getWritableFile(writeSize: 1)

        // When:
        // - wait more than batch obsolescence limit
        // - then request readable file, which should trigger obsolete files deletion
        dateProvider.advance(bySeconds: storage.maxFileAgeForRead + 1)
        _ = orchestrator.getReadableFiles()

        // Then
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "Batch Deleted"))
        DDAssertReflectionEqual(metric.attributes, [
            "metric_type": "batch deleted",
            "track": "track name",
            "consent": "consent value",
            "uploader_delay": [
                "min": upload.minUploadDelay.toMilliseconds,
                "max": upload.maxUploadDelay.toMilliseconds
            ],
            "uploader_window": storage.uploaderWindow.toMilliseconds,
            "in_background": false,
            "batch_age": (storage.maxFileAgeForRead + 1).toMilliseconds,
            "batch_removal_reason": "obsolete",
        ])
    }

    func testWhenDirectoryIsPurged_itSendsBatchDeletedMetrics() throws {
        // Given: some batch
        // - request batch to be created
        // - write more data than allowed directory size limit
        storage.maxDirectorySize = 10 // 10 bytes
        let orchestrator = createOrchestrator()
        let file = try orchestrator.getWritableFile(writeSize: storage.maxDirectorySize + 1)
        try file.append(data: .mockRandom(ofSize: storage.maxDirectorySize + 1))
        let expectedBatchAge = storage.minFileAgeForRead + 1

        // When:
        // - then request new batch, which triggers directory purging
        dateProvider.advance(bySeconds: expectedBatchAge)
        _ = try orchestrator.getWritableFile(writeSize: 1)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "Batch Deleted"))
        DDAssertReflectionEqual(metric.attributes, [
            "metric_type": "batch deleted",
            "track": "track name",
            "consent": "consent value",
            "uploader_delay": [
                "min": upload.minUploadDelay.toMilliseconds,
                "max": upload.maxUploadDelay.toMilliseconds
            ],
            "uploader_window": storage.uploaderWindow.toMilliseconds,
            "in_background": false,
            "batch_age": expectedBatchAge.toMilliseconds,
            "batch_removal_reason": "purged",
        ])
    }

    // MARK: - "Batch Closed" Metric

    func testWhenNewBatchIsStarted_itSendsBatchClosedMetric() throws {
        // Given
        // - request batch to be created
        // - request few writes on that batch
        let orchestrator = createOrchestrator()
        let expectedWrites: [UInt64] = [10, 5, 2]
        try expectedWrites.forEach { writeSize in
            _ = try orchestrator.getWritableFile(writeSize: writeSize)
        }

        // When
        // - wait more than allowed batch age for writes, so next batch request will create another batch
        // - then request another batch, which will close the previous one
        dateProvider.advance(bySeconds: (storage.maxFileAgeForWrite + 1))
        _ = try orchestrator.getWritableFile(writeSize: 1)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "Batch Closed"))
        DDAssertReflectionEqual(metric.attributes, [
            "metric_type": "batch closed",
            "track": "track name",
            "consent": "consent value",
            "uploader_window": storage.uploaderWindow.toMilliseconds,
            "batch_size": expectedWrites.reduce(0, +),
            "batch_events_count": expectedWrites.count,
            "batch_duration": (storage.maxFileAgeForWrite + 1).toMilliseconds
        ])
    }
}
