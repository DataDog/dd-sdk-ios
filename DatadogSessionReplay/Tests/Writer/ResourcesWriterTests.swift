/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import DatadogInternal

@testable import DatadogSessionReplay
@testable import TestUtilities

class ResourcesWriterTests: XCTestCase {
    let resources: [EnrichedResource] = [.mockWith(identifier: "1"), .mockWith(identifier: "2")]
    var scopeMock: FeatureScopeMock! // swiftlint:disable:this implicitly_unwrapped_optional
    var writer: ResourcesWriter! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        scopeMock = FeatureScopeMock()
        writer = ResourcesWriter(scope: scopeMock)
    }

    override func tearDown() {
        writer = nil
        scopeMock = nil
    }

    func test_whenWritesResources_itWritesEachIdentifierOnce() {
        // When
        writer.write(resources: resources + resources)
        writer.write(resources: resources)

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self), resources)
        XCTAssertTrue(scopeMock.dataStoreMock.storage.isEmpty)
    }

    func test_whenWriterIsRecreated_itWritesPreviouslyScheduledResources() {
        // Given
        writer.write(resources: resources)

        // When
        writer = ResourcesWriter(scope: scopeMock)
        writer.write(resources: resources)

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self), resources + resources)
    }

    func test_whenLegacyIdentifiersExist_itDiscardsThemAndWritesResources() throws {
        // Given
        let storeCreation = withUnsafeBytes(of: Date().timeIntervalSince1970) { Data($0) }
        let otherValue = Data("other-value".utf8)
        scopeMock.dataStoreMock.storage = [
            "known-resources": .value(try JSONEncoder().encode(resources.map(\.identifier)), 1),
            "store-creation": .value(storeCreation, 1),
            "other-key": .value(otherValue, 1)
        ]

        // When
        writer = ResourcesWriter(scope: scopeMock)
        writer.write(resources: resources)

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self), resources)
        XCTAssertNil(scopeMock.dataStoreMock.value(forKey: "known-resources"))
        XCTAssertNil(scopeMock.dataStoreMock.value(forKey: "store-creation"))
        XCTAssertEqual(scopeMock.dataStoreMock.value(forKey: "other-key")?.data(expectedVersion: 1), otherValue)
    }
}
#endif
