/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

@testable import DatadogSessionReplay
@testable import TestUtilities

class ResourcesWriterTests: XCTestCase {
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

    func testWhenInitialized_itSetsUpDataStore() {
        XCTAssertNotNil(scopeMock.dataStoreMock.value(forKey: ResourcesWriter.Constants.storeCreationKey))
        XCTAssertNil(scopeMock.dataStoreMock.value(forKey: ResourcesWriter.Constants.knownResourcesKey))
        XCTAssertTrue(scopeMock.telemetryMock.messages.isEmpty)
    }

    func test_whenWritesResources_itDoesWriteRecordsToScope() {
        // When
        writer.write(resources: [.mockRandom()])
        writer.write(resources: [.mockRandom()])
        writer.write(resources: [.mockRandom()])

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self).count, 3)
        XCTAssertTrue(scopeMock.telemetryMock.messages.isEmpty)
    }

    func test_whenWritesSameResourcesToCore_itRemovesDuplicates() throws {
        // Given
        scopeMock.dataStoreMock.setValue(Date().timeIntervalSince1970.asData(), forKey: ResourcesWriter.Constants.storeCreationKey)

        // When
        writer.write(resources: [.mockWith(identifier: "1")])
        writer.write(resources: [.mockWith(identifier: "1")])

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self).count, 1)
        XCTAssertTrue(scopeMock.telemetryMock.messages.isEmpty)
        let data = try XCTUnwrap(scopeMock.dataStoreMock.value(forKey: ResourcesWriter.Constants.knownResourcesKey)?.data())
        XCTAssertGreaterThan(data.count, 0)
    }

    func test_whenReadsKnownDuplicates_itDoesNotWriteRecordsToScope() throws {
        // Given
        let knownIdentifiersData = Set(["1"]).asData(JSONEncoder())!
        scopeMock.dataStoreMock.setValue(knownIdentifiersData, forKey: ResourcesWriter.Constants.knownResourcesKey)
        scopeMock.dataStoreMock.setValue(Date().timeIntervalSince1970.asData(), forKey: ResourcesWriter.Constants.storeCreationKey)
        let writer = ResourcesWriter(scope: scopeMock)

        // When
        writer.write(resources: [.mockWith(identifier: "1")])

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self).count, 0)
        XCTAssertTrue(scopeMock.telemetryMock.messages.isEmpty)
    }

    func test_whenDataStoreIsOlderThan30Days_itClearsKnownDuplicates() throws {
        // Given
        let knownIdentifiersData = Set(["2", "1"]).asData(JSONEncoder())!
        scopeMock.dataStoreMock.setValue(knownIdentifiersData, forKey: ResourcesWriter.Constants.knownResourcesKey)
        scopeMock.dataStoreMock.setValue(
            (Date().timeIntervalSince1970 - 31.days).asData(),
            forKey: ResourcesWriter.Constants.storeCreationKey
        )

        let writer = ResourcesWriter(scope: scopeMock)

        // When
        XCTAssertNil(scopeMock.dataStoreMock.value(forKey: ResourcesWriter.Constants.knownResourcesKey))
        writer.write(resources: [.mockWith(identifier: "1")])

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self).count, 1)
        XCTAssertEqual(
            scopeMock.dataStoreMock.value(forKey: ResourcesWriter.Constants.knownResourcesKey)?.data(),
            Set(["1"]).asData(JSONEncoder())
        )
        XCTAssertTrue(scopeMock.telemetryMock.messages.isEmpty)
    }

    func test_whenKnownResourcesAreBroken_itLogsTelemetry() {
        // Given
        let brokenData = "broken".data(using: .utf8)!
        scopeMock.dataStoreMock.setValue(brokenData, forKey: ResourcesWriter.Constants.knownResourcesKey)

        // When
        _ = ResourcesWriter(scope: scopeMock)

        // Then
        XCTAssertTrue(scopeMock.telemetryMock.messages[0].asError?.message.contains("Failed to decode known identifiers - ") ?? false)
    }

    func test_whenDataStoreCreationIsBroken_itLogsTelemetry() {
        // Given
        let brokenData = "broken".data(using: .utf8)!
        scopeMock.dataStoreMock.setValue(brokenData, forKey: ResourcesWriter.Constants.storeCreationKey)

        // When
        _ = ResourcesWriter(scope: scopeMock)

        // Then
        XCTAssertEqual(scopeMock.telemetryMock.messages[0].asError?.message, "Failed to decode store creation - invalidData")
    }
}
