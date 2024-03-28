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
        XCTAssertNotNil(scopeMock.dataStoreMock.values[ResourcesWriter.Constants.storeCreationKey])
        XCTAssertNil(scopeMock.dataStoreMock.values[ResourcesWriter.Constants.knownResourcesKey])
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
        scopeMock.dataStoreMock.values[ResourcesWriter.Constants.storeCreationKey] = Date().timeIntervalSince1970.asData()

        // When
        writer.write(resources: [.mockWith(identifier: "1")])
        writer.write(resources: [.mockWith(identifier: "1")])

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self).count, 1)
        XCTAssertTrue(scopeMock.telemetryMock.messages.isEmpty)
        let data = try XCTUnwrap(scopeMock.dataStoreMock.values[ResourcesWriter.Constants.knownResourcesKey])
        XCTAssertGreaterThan(data.count, 0)
    }

    func test_whenReadsKnownDuplicates_itDoesNotWriteRecordsToScope() throws {
        // Given
        scopeMock.dataStoreMock.values[ResourcesWriter.Constants.knownResourcesKey] = Set(["1"]).asData()
        scopeMock.dataStoreMock.values[ResourcesWriter.Constants.storeCreationKey] = Date().timeIntervalSince1970.asData()
        let writer = ResourcesWriter(scope: scopeMock)

        // When
        writer.write(resources: [.mockWith(identifier: "1")])

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self).count, 0)
        XCTAssertTrue(scopeMock.telemetryMock.messages.isEmpty)
    }

    func test_whenDataStoreIsOlderThan30Days_itClearsKnownDuplicates() throws {
        // Given
        scopeMock.dataStoreMock.values[ResourcesWriter.Constants.knownResourcesKey] = Set(["2", "1"]).asData()
        scopeMock.dataStoreMock.values[ResourcesWriter.Constants.storeCreationKey] = (Date().timeIntervalSince1970 - 31.days).asData()
        let writer = ResourcesWriter(scope: scopeMock)

        // When
        XCTAssertNil(scopeMock.dataStoreMock.values[ResourcesWriter.Constants.knownResourcesKey])
        writer.write(resources: [.mockWith(identifier: "1")])

        // Then
        XCTAssertEqual(scopeMock.eventsWritten(ofType: EnrichedResource.self).count, 1)
        XCTAssertEqual(scopeMock.dataStoreMock.values[ResourcesWriter.Constants.knownResourcesKey], Set(["1"]).asData())
        XCTAssertTrue(scopeMock.telemetryMock.messages.isEmpty)
    }

    func test_whenKnownResourcesAreBroken_itLogsTelemetry() {
        // Given
        scopeMock.dataStoreMock.values[ResourcesWriter.Constants.knownResourcesKey] = "broken".data(using: .utf8)

        // When
        _ = ResourcesWriter(scope: scopeMock)

        // Then
        XCTAssertTrue(scopeMock.telemetryMock.messages[0].asError?.message.contains("Failed to decode known identifiers - ") ?? false)
    }

    func test_whenDataStoreCreationIsBroken_itLogsTelemetry() {
        // Given
        scopeMock.dataStoreMock.values[ResourcesWriter.Constants.storeCreationKey] = "broken".data(using: .utf8)

        // When
        _ = ResourcesWriter(scope: scopeMock)

        // Then
        XCTAssertEqual(scopeMock.telemetryMock.messages[0].asError?.message, "Failed to decode store creation - invalidData")
    }
}
