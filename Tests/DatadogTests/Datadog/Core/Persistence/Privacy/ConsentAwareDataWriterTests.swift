/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private class FileWriterMock: FileWriterType {
    var dataWritten: Encodable?

    func write<T>(value: T) where T: Encodable {
        dataWritten = value
    }
}

class ConsentAwareDataWriterTests: XCTestCase {
    private let queue = DispatchQueue(label: "dd-tests-write", target: .global(qos: .utility))
    private let unauthorizedWriter = FileWriterMock()
    private let authorizedWriter = FileWriterMock()

    override func setUp() {
        super.setUp()
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    // MARK: - Testing Initial Consent

    func testWhenInitializedWithConsentGranted_thenItWritesDataToAuthorizedFolder() {
        // When
        let writer = ConsentAwareDataWriter(
            consentProvider: ConsentProvider(initialConsent: .granted),
            queue: queue,
            unauthorizedFileWriter: unauthorizedWriter,
            authorizedFileWriter: authorizedWriter
        )

        // Then
        writer.write(value: "authorized data")

        waitForAsyncWrite(on: queue)
        XCTAssertNil(unauthorizedWriter.dataWritten)
        XCTAssertEqual(authorizedWriter.dataWritten as? String, "authorized data")
    }

    func testWhenInitializedWithConsentPending_thenItWritesDataToUnauthorizedFolder() {
        // When
        let writer = ConsentAwareDataWriter(
            consentProvider: ConsentProvider(initialConsent: .pending),
            queue: queue,
            unauthorizedFileWriter: unauthorizedWriter,
            authorizedFileWriter: authorizedWriter
        )

        // Then
        writer.write(value: "unauthorized data")

        waitForAsyncWrite(on: queue)
        XCTAssertNil(authorizedWriter.dataWritten)
        XCTAssertEqual(unauthorizedWriter.dataWritten as? String, "unauthorized data")
    }

    func testWhenInitializedWithConsentNotGranted_thenItDoesNotWriteDataToAnyFolder() {
        // When
        let writer = ConsentAwareDataWriter(
            consentProvider: ConsentProvider(initialConsent: .notGranted),
            queue: queue,
            unauthorizedFileWriter: unauthorizedWriter,
            authorizedFileWriter: authorizedWriter
        )

        // Then
        writer.write(value: "rejected data")

        waitForAsyncWrite(on: queue)
        XCTAssertNil(unauthorizedWriter.dataWritten)
        XCTAssertNil(authorizedWriter.dataWritten)
    }

    // MARK: - Testing Consent Changes

    func testWhenConsentChangesToGranted_thenItStartsWrittingDataToAuthorizedFolder() {
        let initialConsent: TrackingConsent = [.pending, .notGranted].randomElement()!
        let consentProvider = ConsentProvider(initialConsent: initialConsent)
        let writer = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            queue: queue,
            unauthorizedFileWriter: unauthorizedWriter,
            authorizedFileWriter: authorizedWriter
        )

        // When
        consentProvider.changeConsent(to: .granted)

        // Then
        writer.write(value: "authorized data")

        waitForAsyncWrite(on: queue)
        XCTAssertNil(unauthorizedWriter.dataWritten)
        XCTAssertEqual(authorizedWriter.dataWritten as? String, "authorized data")
    }

    func testWhenConsentChangesPending_thenItStartsWrittingDataToUnauthorizedFolder() {
        let initialConsent: TrackingConsent = [.granted, .notGranted].randomElement()!
        let consentProvider = ConsentProvider(initialConsent: initialConsent)
        let writer = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            queue: queue,
            unauthorizedFileWriter: unauthorizedWriter,
            authorizedFileWriter: authorizedWriter
        )

        // When
        consentProvider.changeConsent(to: .pending)

        // Then
        writer.write(value: "unauthorized data")

        waitForAsyncWrite(on: queue)
        XCTAssertEqual(unauthorizedWriter.dataWritten as? String, "unauthorized data")
        XCTAssertNil(authorizedWriter.dataWritten)
    }

    func testWhenConsentChangesToNotGranted_thenItStopsWrittingDataToAnyFolder() {
        let initialConsent: TrackingConsent = [.granted, .pending].randomElement()!
        let consentProvider = ConsentProvider(initialConsent: initialConsent)
        let writer = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            queue: queue,
            unauthorizedFileWriter: unauthorizedWriter,
            authorizedFileWriter: authorizedWriter
        )

        // When
        consentProvider.changeConsent(to: .notGranted)

        // Then
        writer.write(value: "rejected data")

        waitForAsyncWrite(on: queue)
        XCTAssertNil(unauthorizedWriter.dataWritten)
        XCTAssertNil(authorizedWriter.dataWritten)
    }

    // MARK: - Thread Safety

    func testChangingConsentAndCallingWriterFromDifferentThreadsShouldNotCrash() {
        func randomConsent() -> TrackingConsent {
            return [.granted, .pending, .notGranted].randomElement()!
        }

        let consentProvider = ConsentProvider(initialConsent: randomConsent())
        let writer = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            queue: queue,
            unauthorizedFileWriter: unauthorizedWriter,
            authorizedFileWriter: authorizedWriter
        )

        DispatchQueue.concurrentPerform(iterations: 10_000) { iteration in
            if iteration % 2 == 0 {
                consentProvider.changeConsent(to: randomConsent())
            } else {
                writer.write(value: "data \(iteration)")
            }
        }

        waitForAsyncWrite(on: queue)
        XCTAssertNotNil(unauthorizedWriter.dataWritten, "There should be some unauthorized data written.")
        XCTAssertNotNil(authorizedWriter.dataWritten, "There should be some authorized data written.")
    }

    // MARK: - Helpers

    private func waitForAsyncWrite(on queue: DispatchQueue) {
        queue.sync {}
    }
}
