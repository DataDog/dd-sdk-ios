/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class ConsentAwareDataWriterTests: XCTestCase {
    private let queue = DispatchQueue(label: "dd-tests-write", target: .global(qos: .utility))
    private let unauthorizedWriter = FileWriterMock()
    private let authorizedWriter = FileWriterMock()
    private lazy var dataProcessorFactory = DataProcessorFactory(
        unauthorizedFileWriter: unauthorizedWriter,
        authorizedFileWriter: authorizedWriter
    )
    private lazy var dataMigratorFactory = DataMigratorFactory(
        directories: temporaryFeatureDirectories
    )

    override func setUp() {
        super.setUp()
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    // MARK: - Writing Data on Initial Consent

    func testWhenInitializedWithConsentGranted_thenItWritesDataToAuthorizedFolder() {
        // When
        let writer = ConsentAwareDataWriter(
            consentProvider: ConsentProvider(initialConsent: .granted),
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        // Then
        writer.write(value: "authorized data")

        waitForOperationCompletion(on: queue)
        XCTAssertNil(unauthorizedWriter.dataWritten)
        XCTAssertEqual(authorizedWriter.dataWritten as? String, "authorized data")
    }

    func testWhenInitializedWithConsentPending_thenItWritesDataToUnauthorizedFolder() {
        // When
        let writer = ConsentAwareDataWriter(
            consentProvider: ConsentProvider(initialConsent: .pending),
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        // Then
        writer.write(value: "unauthorized data")

        waitForOperationCompletion(on: queue)
        XCTAssertNil(authorizedWriter.dataWritten)
        XCTAssertEqual(unauthorizedWriter.dataWritten as? String, "unauthorized data")
    }

    func testWhenInitializedWithConsentNotGranted_thenItDoesNotWriteDataToAnyFolder() {
        // When
        let writer = ConsentAwareDataWriter(
            consentProvider: ConsentProvider(initialConsent: .notGranted),
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        // Then
        writer.write(value: "rejected data")

        waitForOperationCompletion(on: queue)
        XCTAssertNil(unauthorizedWriter.dataWritten)
        XCTAssertNil(authorizedWriter.dataWritten)
    }

    // MARK: - Writing Data After Consent Change

    func testWhenConsentChangesToGranted_thenItStartsWritingDataToAuthorizedFolder() {
        let initialConsent: TrackingConsent = [.pending, .notGranted].randomElement()!
        let consentProvider = ConsentProvider(initialConsent: initialConsent)
        let writer = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        // When
        consentProvider.changeConsent(to: .granted)

        // Then
        writer.write(value: "authorized data")

        waitForOperationCompletion(on: queue)
        XCTAssertNil(unauthorizedWriter.dataWritten)
        XCTAssertEqual(authorizedWriter.dataWritten as? String, "authorized data")
    }

    func testWhenConsentChangesToPending_thenItStartsWritingDataToUnauthorizedFolder() {
        let initialConsent: TrackingConsent = [.granted, .notGranted].randomElement()!
        let consentProvider = ConsentProvider(initialConsent: initialConsent)
        let writer = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        // When
        consentProvider.changeConsent(to: .pending)

        // Then
        writer.write(value: "unauthorized data")

        waitForOperationCompletion(on: queue)
        XCTAssertEqual(unauthorizedWriter.dataWritten as? String, "unauthorized data")
        XCTAssertNil(authorizedWriter.dataWritten)
    }

    func testWhenConsentChangesToNotGranted_thenItStopsWritingDataToAnyFolder() {
        let initialConsent: TrackingConsent = [.granted, .pending].randomElement()!
        let consentProvider = ConsentProvider(initialConsent: initialConsent)
        let writer = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        // When
        consentProvider.changeConsent(to: .notGranted)

        // Then
        writer.write(value: "rejected data")

        waitForOperationCompletion(on: queue)
        XCTAssertNil(unauthorizedWriter.dataWritten)
        XCTAssertNil(authorizedWriter.dataWritten)
    }

    // MARK: - Data Migration

    func testGivenDataWrittenInUnauthorizedFolder_whenInitializedWithAnyConsent_thenItDeletesAllDataInUnauthorizedFolder() throws {
        let directories = temporaryFeatureDirectories

        // Given
        directories.unauthorized.createMockFiles(count: 10)
        XCTAssertEqual(try directories.unauthorized.files().count, 10)

        // When
        let initialConsent: TrackingConsent = .mockRandom()
        _ = ConsentAwareDataWriter(
            consentProvider: ConsentProvider(initialConsent: initialConsent),
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        // Then
        waitForOperationCompletion(on: queue)
        XCTAssertEqual(try directories.unauthorized.files().count, 0)
    }

    func testGivenDataWrittenWithConsentPending_whenConsentChangesToNotGranted_itDeletesAllDataInUnauthorizedFolder() throws {
        let directories = temporaryFeatureDirectories

        // Given
        let consentProvider = ConsentProvider(initialConsent: .pending)
        _ = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        waitForOperationCompletion(on: queue)
        directories.unauthorized.createMockFiles(count: 10)
        XCTAssertEqual(try directories.unauthorized.files().count, 10)

        // When
        consentProvider.changeConsent(to: .notGranted)

        // Then
        waitForOperationCompletion(on: queue)
        XCTAssertEqual(try directories.unauthorized.files().count, 0)
    }

    func testGivenDataWrittenWithConsentPending_whenConsentChangesToGranted_itMovesAllDataToAuthorizedFolder() throws {
        let directories = temporaryFeatureDirectories

        // Given
        let consentProvider = ConsentProvider(initialConsent: .pending)
        _ = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        waitForOperationCompletion(on: queue)
        directories.unauthorized.createMockFiles(count: 10)
        XCTAssertEqual(try directories.unauthorized.files().count, 10)
        XCTAssertEqual(try directories.authorized.files().count, 0)

        // When
        consentProvider.changeConsent(to: .granted)

        // Then
        waitForOperationCompletion(on: queue)
        XCTAssertEqual(try directories.unauthorized.files().count, 0)
        XCTAssertEqual(try directories.authorized.files().count, 10)
    }

    func testGivenDataWrittenInAuthorizedFolder_whenConsentChanges_itDoesNotModifyAuthorizedFolder() throws {
        let directories = temporaryFeatureDirectories

        // Given
        let consentProvider = ConsentProvider(initialConsent: .granted)
        _ = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        waitForOperationCompletion(on: queue)
        directories.authorized.createMockFiles(count: 10)
        XCTAssertEqual(try directories.authorized.files().count, 10)

        // When
        let nextConsents: [TrackingConsent] = [.granted, .pending, .notGranted].shuffled()
        nextConsents.forEach { nextConsent in
            consentProvider.changeConsent(to: nextConsent)
        }

        // Then
        waitForOperationCompletion(on: queue)
        XCTAssertEqual(try directories.authorized.files().count, 10)
    }

    // MARK: - Thread Safety

    func testChangingConsentAndCallingWriterFromDifferentThreadsShouldNotCrash() {
        let consentProvider = ConsentProvider(initialConsent: .mockRandom())
        let writer = ConsentAwareDataWriter(
            consentProvider: consentProvider,
            readWriteQueue: queue,
            dataProcessorFactory: dataProcessorFactory,
            dataMigratorFactory: dataMigratorFactory
        )

        DispatchQueue.concurrentPerform(iterations: 10_000) { iteration in
            if iteration % 2 == 0 {
                consentProvider.changeConsent(to: .mockRandom())
            } else {
                writer.write(value: "data \(iteration)")
            }
        }

        waitForOperationCompletion(on: queue)
        XCTAssertNotNil(unauthorizedWriter.dataWritten, "There should be some unauthorized data written.")
        XCTAssertNotNil(authorizedWriter.dataWritten, "There should be some authorized data written.")
    }

    // MARK: - Helpers

    private func waitForOperationCompletion(on queue: DispatchQueue) {
        queue.sync {}
    }
}
