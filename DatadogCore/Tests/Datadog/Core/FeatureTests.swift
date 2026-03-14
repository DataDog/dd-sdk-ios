/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogCore

class FeatureStorageTests: XCTestCase {
    private var storage: FeatureStorage! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        storage = FeatureStorage(
            featureName: .mockAny(),
            directories: temporaryFeatureDirectories,
            dateProvider: RelativeDateProvider(advancingBySeconds: 0.01),
            performance: .mockRandom(),
            encryption: nil,
            backgroundTasksEnabled: .mockRandom(),
            telemetry: NOPTelemetry()
        )
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        temporaryFeatureDirectories.delete()
        storage = nil
        super.tearDown()
    }

    // MARK: - Writing data

    func testWhenWritingEventsWithoutForcingNewBatch_itShouldWriteAllEventsToTheSameBatch() async throws {
        // When
        await storage.writer(for: .granted).write(value: ["event1": "1"])
        await storage.writer(for: .granted).write(value: ["event2": "2"])
        await storage.writer(for: .granted).write(value: ["event3": "3"])

        // Then
        await storage.setIgnoreFilesAgeWhenReading(to: true)

        let batches = await storage.reader.readNextBatches(1)
        let batch = try XCTUnwrap(batches.first)
        XCTAssertEqual(batch.events.count, 3, "All 3 events should be written to the same batch")
        await storage.reader.markBatchAsRead(batch)

        let remaining = await storage.reader.readNextBatches(1)
        XCTAssertTrue(remaining.isEmpty, "There must be no other batches")
    }

    // MARK: - Behaviours on tracking consent

    func testWhenWritingEventsInDifferentConsents_itOnlyReadsGrantedEvents() async throws {
        // When
        await storage.writer(for: .granted).write(value: ["event.consent": "granted"])
        await storage.writer(for: .pending).write(value: ["event.consent": "pending"])
        await storage.writer(for: .notGranted).write(value: ["event.consent": "notGranted"])

        // Then
        await storage.setIgnoreFilesAgeWhenReading(to: true)

        let batches = await storage.reader.readNextBatches(1)
        let batch = try XCTUnwrap(batches.first)
        XCTAssertEqual(batch.events.map { $0.data.utf8String }, [#"{"event.consent":"granted"}"#])
        await storage.reader.markBatchAsRead(batch)

        let remaining = await storage.reader.readNextBatches(1)
        XCTAssertTrue(remaining.isEmpty, "There must be no other batches")
    }

    func testGivenEventsWrittenInDifferentConsents_whenChangingConsentToGranted_itMakesPendingEventsReadable() async throws {
        // Given
        await storage.writer(for: .granted).write(value: ["event.consent": "granted"])
        await storage.writer(for: .pending).write(value: ["event.consent": "pending"])
        await storage.writer(for: .notGranted).write(value: ["event.consent": "notGranted"])

        // When
        await storage.migrateUnauthorizedData(toConsent: .granted)

        // Then
        await storage.setIgnoreFilesAgeWhenReading(to: true)

        var batches = await storage.reader.readNextBatches(1)
        var batch = try XCTUnwrap(batches.first)
        XCTAssertEqual(batch.events.map { $0.data.utf8String }, [#"{"event.consent":"granted"}"#])
        await storage.reader.markBatchAsRead(batch)

        batches = await storage.reader.readNextBatches(1)
        batch = try XCTUnwrap(batches.first)
        XCTAssertEqual(batch.events.map { $0.data.utf8String }, [#"{"event.consent":"pending"}"#])
        await storage.reader.markBatchAsRead(batch)

        let remaining = await storage.reader.readNextBatches(1)
        XCTAssertTrue(remaining.isEmpty, "There must be no other batches")
    }

    func testGivenEventsWrittenInDifferentConsents_whenChangingConsentToNotGranted_itDeletesPendingEvents() async throws {
        // Given
        await storage.writer(for: .granted).write(value: ["event.consent": "granted"])
        await storage.writer(for: .pending).write(value: ["event.consent": "pending"])
        await storage.writer(for: .notGranted).write(value: ["event.consent": "notGranted"])

        // When
        await storage.migrateUnauthorizedData(toConsent: .notGranted)

        // Then
        await storage.setIgnoreFilesAgeWhenReading(to: true)

        let batches3 = await storage.reader.readNextBatches(1)
        let batch = try XCTUnwrap(batches3.first)
        XCTAssertEqual(batch.events.map { $0.data.utf8String }, [#"{"event.consent":"granted"}"#])
        await storage.reader.markBatchAsRead(batch)

        var remaining = await storage.reader.readNextBatches(1)
        XCTAssertTrue(remaining.isEmpty, "There must be no other batches")

        await storage.migrateUnauthorizedData(toConsent: .granted)
        remaining = await storage.reader.readNextBatches(1)
        XCTAssertTrue(
            remaining.isEmpty,
            "There must be no other batches, because pending events were deleted"
        )
    }

    // MARK: - Data migration

    private let unauthorizedDirectory = temporaryFeatureDirectories.unauthorized
    private let authorizedDirectory = temporaryFeatureDirectories.authorized

    func testDeletingPendingData() async throws {
        // Given
        unauthorizedDirectory.createMockFiles(count: 10)
        XCTAssertEqual(try unauthorizedDirectory.files().count, 10)

        // When
        await storage.clearUnauthorizedData()

        // Then
        XCTAssertEqual(try unauthorizedDirectory.files().count, 0)
    }

    func testDeletingAllData() async throws {
        // Given
        unauthorizedDirectory.createMockFiles(count: 10)
        authorizedDirectory.createMockFiles(count: 10)
        XCTAssertEqual(try unauthorizedDirectory.files().count, 10)
        XCTAssertEqual(try authorizedDirectory.files().count, 10)

        // When
        await storage.clearAllData()

        // Then
        XCTAssertEqual(try unauthorizedDirectory.files().count, 0)
        XCTAssertEqual(try authorizedDirectory.files().count, 0)
    }
}
