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
    private let queue = DispatchQueue(label: "feature-storage-test")
    private var storage: FeatureStorage! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        storage = FeatureStorage(
            featureName: .mockAny(),
            queue: queue,
            directories: temporaryFeatureDirectories,
            dateProvider: RelativeDateProvider(advancingBySeconds: 0.01),
            performance: .mockRandom(),
            encryption: nil,
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

    func testWhenWritingEventsWithoutForcingNewBatch_itShouldWriteAllEventsToTheSameBatch() throws {
        // When
        storage.writer(for: .mockWith(trackingConsent: .granted)).write(value: ["event1": "1"])
        storage.writer(for: .mockWith(trackingConsent: .granted)).write(value: ["event2": "2"])
        storage.writer(for: .mockWith(trackingConsent: .granted)).write(value: ["event3": "3"])

        // Then
        storage.setIgnoreFilesAgeWhenReading(to: true)

        let batch = try XCTUnwrap(storage.reader.readNextBatch(context: .mockAny()))
        XCTAssertEqual(batch.events.count, 3, "All 3 events should be written to the same batch")
        storage.reader.markBatchAsRead(batch)

        XCTAssertNil(storage.reader.readNextBatch(context: .mockAny()), "There must be no other batche")
    }

    func testWhenWritingEventsWithForcingNewBatch_itShouldWriteEachEventToSeparateBatch() throws {
        // When
        storage.writer(for: .mockWith(trackingConsent: .granted), forceNewBatch: true).write(value: ["event1": "1"])
        storage.writer(for: .mockWith(trackingConsent: .granted), forceNewBatch: true).write(value: ["event2": "2"])
        storage.writer(for: .mockWith(trackingConsent: .granted), forceNewBatch: true).write(value: ["event3": "3"])

        // Then
        storage.setIgnoreFilesAgeWhenReading(to: true)

        var batch = try XCTUnwrap(storage.reader.readNextBatch(context: .mockAny()))
        XCTAssertEqual(batch.events.count, 1)
        storage.reader.markBatchAsRead(batch)

        batch = try XCTUnwrap(storage.reader.readNextBatch(context: .mockAny()))
        XCTAssertEqual(batch.events.count, 1)
        storage.reader.markBatchAsRead(batch)

        batch = try XCTUnwrap(storage.reader.readNextBatch(context: .mockAny()))
        XCTAssertEqual(batch.events.count, 1)
        storage.reader.markBatchAsRead(batch)

        XCTAssertNil(storage.reader.readNextBatch(context: .mockAny()), "There must be no other batches")
    }

    // MARK: - Behaviours on tracking consent

    func testWhenWritingEventsInDifferentConsents_itOnlyReadsGrantedEvents() throws {
        // When
        storage.writer(for: .mockWith(trackingConsent: .granted)).write(value: ["event.consent": "granted"])
        storage.writer(for: .mockWith(trackingConsent: .pending)).write(value: ["event.consent": "pending"])
        storage.writer(for: .mockWith(trackingConsent: .notGranted)).write(value: ["event.consent": "notGranted"])

        // Then
        storage.setIgnoreFilesAgeWhenReading(to: true)

        let batch = try XCTUnwrap(storage.reader.readNextBatch(context: .mockAny()))
        XCTAssertEqual(batch.events.map { $0.data.utf8String }, [#"{"event.consent":"granted"}"#])
        storage.reader.markBatchAsRead(batch)

        XCTAssertNil(storage.reader.readNextBatch(context: .mockAny()), "There must be no other batches")
    }

    func testGivenEventsWrittenInDifferentConsents_whenChangingConsentToGranted_itMakesPendingEventsReadable() throws {
        // Given
        storage.writer(for: .mockWith(trackingConsent: .granted), forceNewBatch: false).write(value: ["event.consent": "granted"])
        storage.writer(for: .mockWith(trackingConsent: .pending), forceNewBatch: false).write(value: ["event.consent": "pending"])
        storage.writer(for: .mockWith(trackingConsent: .notGranted), forceNewBatch: false).write(value: ["event.consent": "notGranted"])

        // When
        storage.migrateUnauthorizedData(toConsent: .granted)

        // Then
        storage.setIgnoreFilesAgeWhenReading(to: true)

        var batch = try XCTUnwrap(storage.reader.readNextBatch(context: .mockAny()))
        XCTAssertEqual(batch.events.map { $0.data.utf8String }, [#"{"event.consent":"granted"}"#])
        storage.reader.markBatchAsRead(batch)

        batch = try XCTUnwrap(storage.reader.readNextBatch(context: .mockAny()))
        XCTAssertEqual(batch.events.map { $0.data.utf8String }, [#"{"event.consent":"pending"}"#])
        storage.reader.markBatchAsRead(batch)

        XCTAssertNil(storage.reader.readNextBatch(context: .mockAny()), "There must be no other batches")
    }

    func testGivenEventsWrittenInDifferentConsents_whenChangingConsentToNotGranted_itDeletesPendingEvents() throws {
        // Given
        storage.writer(for: .mockWith(trackingConsent: .granted), forceNewBatch: false).write(value: ["event.consent": "granted"])
        storage.writer(for: .mockWith(trackingConsent: .pending), forceNewBatch: false).write(value: ["event.consent": "pending"])
        storage.writer(for: .mockWith(trackingConsent: .notGranted), forceNewBatch: false).write(value: ["event.consent": "notGranted"])

        // When
        storage.migrateUnauthorizedData(toConsent: .notGranted)

        // Then
        storage.setIgnoreFilesAgeWhenReading(to: true)

        let batch = try XCTUnwrap(storage.reader.readNextBatch(context: .mockAny()))
        XCTAssertEqual(batch.events.map { $0.data.utf8String }, [#"{"event.consent":"granted"}"#])
        storage.reader.markBatchAsRead(batch)

        XCTAssertNil(storage.reader.readNextBatch(context: .mockAny()), "There must be no other batches")

        storage.migrateUnauthorizedData(toConsent: .granted)
        XCTAssertNil(storage.reader.readNextBatch(context: .mockAny()), "There must be no other batches, because pending events were deleted")
    }

    // MARK: - Data migration

    private let unauthorizedDirectory = temporaryFeatureDirectories.unauthorized
    private let authorizedDirectory = temporaryFeatureDirectories.authorized

    func testDeletingPendingData() throws {
        // Given
        unauthorizedDirectory.createMockFiles(count: 10)
        XCTAssertEqual(try unauthorizedDirectory.files().count, 10)

        // When
        storage.clearUnauthorizedData()

        // Then
        try queue.sync {
            XCTAssertEqual(try unauthorizedDirectory.files().count, 0)
        }
    }

    func testDeletingAllData() throws {
        // Given
        unauthorizedDirectory.createMockFiles(count: 10)
        authorizedDirectory.createMockFiles(count: 10)
        XCTAssertEqual(try unauthorizedDirectory.files().count, 10)
        XCTAssertEqual(try authorizedDirectory.files().count, 10)

        // When
        storage.clearAllData()

        // Then
        try queue.sync {
            XCTAssertEqual(try unauthorizedDirectory.files().count, 0)
            XCTAssertEqual(try authorizedDirectory.files().count, 0)
        }
    }
}
