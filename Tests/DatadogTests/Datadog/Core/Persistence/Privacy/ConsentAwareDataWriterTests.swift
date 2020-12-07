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

    override func setUp() {
        super.setUp()
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    func testWhenInitializedWithConsentGranted_thenItWritesDataToAuthorizedFolder() {
        let unauthorizedWriter = FileWriterMock()
        let authorizedWriter = FileWriterMock()

        // When
        let writer = ConsentAwareDataWriter(
            initialConsent: .granted,
            queue: queue,
            unauthorizedFileWriter: unauthorizedWriter,
            authorizedFileWriter: authorizedWriter
        )

        // Then
        writer.write(value: "abc")

        XCTAssertNil(unauthorizedWriter.dataWritten)
        XCTAssertEqual(authorizedWriter.dataWritten as? String, "abc")
    }

    func testWhenInitializedWithConsentPending_thenItWritesDataToUnauthorizedFolder() {
        let unauthorizedWriter = FileWriterMock()
        let authorizedWriter = FileWriterMock()

        // When
        let writer = ConsentAwareDataWriter(
            initialConsent: .pending,
            queue: queue,
            unauthorizedFileWriter: unauthorizedWriter,
            authorizedFileWriter: authorizedWriter
        )

        // Then
        writer.write(value: "abc")

        XCTAssertNil(authorizedWriter.dataWritten)
        XCTAssertEqual(unauthorizedWriter.dataWritten as? String, "abc")
    }

    func testWhenInitializedWithConsentNotGranted_thenItDoesNotWriteDataToAnyFolder() {
        let unauthorizedWriter = FileWriterMock()
        let authorizedWriter = FileWriterMock()

        // When
        let writer = ConsentAwareDataWriter(
            initialConsent: .notGranted,
            queue: queue,
            unauthorizedFileWriter: unauthorizedWriter,
            authorizedFileWriter: authorizedWriter
        )

        // Then
        writer.write(value: "abc")

        XCTAssertNil(unauthorizedWriter.dataWritten)
        XCTAssertNil(authorizedWriter.dataWritten)
    }
}
