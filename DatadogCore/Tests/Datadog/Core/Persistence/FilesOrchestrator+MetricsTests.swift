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
    private var storage: StoragePerformanceMock!
    private var upload: UploadPerformanceMock!

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
                uploaderPerformance: upload,
                backgroundTasksEnabled: .mockAny()
            )
        )
    }

    func testWhenReadableFileIsDeleted_itSendsBatchDeletedMetric() async throws {
        let orchestrator = createOrchestrator()
        let expectedBatchAge = storage.minFileAgeForRead + 1
        _ = try await orchestrator.getWritableFile(writeSize: 1)
        dateProvider.advance(bySeconds: expectedBatchAge)
        let file = try XCTUnwrap(try await orchestrator.getWritableFile(writeSize: 1) as? ReadableFile)
        dateProvider.advance(bySeconds: expectedBatchAge)
        await orchestrator.delete(readableFile: file, deletionReason: .intakeCode(responseCode: 202))
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "Batch Deleted"))
        DDAssertJSONEqual(metric.attributes, [
            "metric_type": "batch deleted",
            "track": "track name",
            "consent": "consent value",
            "uploader_delay": [
                "min": upload.minUploadDelay.dd.toMilliseconds,
                "max": upload.maxUploadDelay.dd.toMilliseconds
            ],
            "uploader_window": storage.uploaderWindow.dd.toMilliseconds,
            "in_background": false,
            "background_tasks_enabled": false,
            "batch_age": expectedBatchAge.dd.toMilliseconds,
            "batch_removal_reason": "intake-code-202",
            "pending_batches": 1
        ])
        XCTAssertEqual(metric.sampleRate, BatchDeletedMetric.sampleRate)
    }

    func testWhenObsoleteFileIsDeleted_itSendsBatchDeletedMetric() async throws {
        let orchestrator = createOrchestrator()
        _ = try await orchestrator.getWritableFile(writeSize: 1)
        dateProvider.advance(bySeconds: storage.maxFileAgeForRead + 1)
        _ = await orchestrator.getReadableFiles(excludingFilesNamed: [], limit: .max)
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "Batch Deleted"))
        DDAssertJSONEqual(metric.attributes, [
            "metric_type": "batch deleted",
            "track": "track name",
            "consent": "consent value",
            "uploader_delay": [
                "min": upload.minUploadDelay.dd.toMilliseconds,
                "max": upload.maxUploadDelay.dd.toMilliseconds
            ],
            "uploader_window": storage.uploaderWindow.dd.toMilliseconds,
            "in_background": false,
            "background_tasks_enabled": false,
            "batch_age": (storage.maxFileAgeForRead + 1).dd.toMilliseconds,
            "batch_removal_reason": "obsolete",
            "pending_batches": 0
        ])
        XCTAssertEqual(metric.sampleRate, BatchDeletedMetric.sampleRate)
    }

    func testWhenDirectoryIsPurged_itSendsBatchDeletedMetrics() async throws {
        storage.maxDirectorySize = 10
        let orchestrator = createOrchestrator()
        let file = try await orchestrator.getWritableFile(writeSize: storage.maxDirectorySize.asUInt64() + 1)
        try file.append(data: .mockRandom(ofSize: storage.maxDirectorySize + 1))
        let expectedBatchAge = storage.minFileAgeForRead + 1
        dateProvider.advance(bySeconds: expectedBatchAge)
        _ = try await orchestrator.getWritableFile(writeSize: 1)
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "Batch Deleted"))
        DDAssertJSONEqual(metric.attributes, [
            "metric_type": "batch deleted",
            "track": "track name",
            "consent": "consent value",
            "uploader_delay": [
                "min": upload.minUploadDelay.dd.toMilliseconds,
                "max": upload.maxUploadDelay.dd.toMilliseconds
            ],
            "uploader_window": storage.uploaderWindow.dd.toMilliseconds,
            "in_background": false,
            "background_tasks_enabled": false,
            "batch_age": expectedBatchAge.dd.toMilliseconds,
            "batch_removal_reason": "purged",
            "pending_batches": 0
        ])
        XCTAssertEqual(metric.sampleRate, BatchDeletedMetric.sampleRate)
    }

    func testWhenNewBatchIsStarted_itSendsBatchClosedMetric() async throws {
        let orchestrator = createOrchestrator()
        let expectedWrites: [UInt64] = [10, 5, 2]
        let expectedWriteDelays: [TimeInterval] = [
            storage.maxFileAgeForWrite * 0.25,
            storage.maxFileAgeForWrite * 0.45,
        ]
        _ = try await orchestrator.getWritableFile(writeSize: expectedWrites[0])
        dateProvider.advance(bySeconds: expectedWriteDelays[0])
        _ = try await orchestrator.getWritableFile(writeSize: expectedWrites[1])
        dateProvider.advance(bySeconds: expectedWriteDelays[1])
        _ = try await orchestrator.getWritableFile(writeSize: expectedWrites[2])
        dateProvider.advance(bySeconds: storage.maxFileAgeForWrite + 1)
        _ = try await orchestrator.getWritableFile(writeSize: 1)
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: "Batch Closed"))
        DDAssertReflectionEqual(metric.attributes, [
            "metric_type": "batch closed",
            "track": "track name",
            "consent": "consent value",
            "uploader_window": storage.uploaderWindow.dd.toMilliseconds,
            "batch_size": expectedWrites.reduce(0, +),
            "batch_events_count": expectedWrites.count,
            "batch_duration": expectedWriteDelays.reduce(0, +).dd.toMilliseconds
        ])
        XCTAssertEqual(metric.sampleRate, BatchClosedMetric.sampleRate)
    }
}
