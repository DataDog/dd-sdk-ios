/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogSessionReplay
@testable import TestUtilities

class ResourcesWriterTests: XCTestCase {
    func testWhenFeatureScopeIsConnected_itWritesResourcesToCore() {
        // Given
        let core = PassthroughCoreMock()

        // When
        let writer = ResourcesWriter(core: core)

        // Then
        writer.write(resources: [.mockRandom()])
        writer.write(resources: [.mockRandom()])
        writer.write(resources: [.mockRandom()])

        XCTAssertEqual(core.events(ofType: EnrichedResource.self).count, 3)
    }

    func testWhenFeatureScopeIsNotConnected_itDoesNotWriteRecordsToCore() throws {
        // Given
        let core = SingleFeatureCoreMock<MockFeature>()
        let feature = MockFeature()
        try core.register(feature: feature)

        // When
        let writer = ResourcesWriter(core: core)

        // Then
        writer.write(resources: [.mockRandom()])

        XCTAssertEqual(core.events(ofType: EnrichedResource.self).count, 0)
    }

    func testWritesSameResourcesToCore_andRemovesDuplicates() throws {
        // Given
        let dataStore = DataStoreMock()
        dataStore.values[ResourcesWriter.Constants.storeCreationKey] = Date().timeIntervalSince1970.asData()
        let core = PassthroughCoreMock(dataStore: dataStore)

        // When
        let writer = ResourcesWriter(core: core)
        writer.write(resources: [.mockWith(identifier: "1")])
        writer.write(resources: [.mockWith(identifier: "1")])

        // Then
        XCTAssertEqual(core.events(ofType: EnrichedResource.self).count, 1)
        let data = try XCTUnwrap(dataStore.values[ResourcesWriter.Constants.knownResourcesKey])
        XCTAssertGreaterThan(data.count, 0)
    }

    func testWhenReadsKnownDuplicates_itDoesNotWriteRecordsToCore() throws {
        // Given
        let dataStore = DataStoreMock()
        dataStore.values[ResourcesWriter.Constants.knownResourcesKey] = Set(["1"]).asData()
        dataStore.values[ResourcesWriter.Constants.storeCreationKey] = Date().timeIntervalSince1970.asData()
        let core = PassthroughCoreMock(dataStore: dataStore)

        // When
        let writer = ResourcesWriter(core: core)

        // Then
        writer.write(resources: [.mockWith(identifier: "1")])
        XCTAssertEqual(core.events(ofType: EnrichedResource.self).count, 0)
    }

    func testWhenDataStoreIsOlderThan30Days_itClearsKnownDuplicates() throws {
        // Given
        let dataStore = DataStoreMock()
        dataStore.values[ResourcesWriter.Constants.knownResourcesKey] = Set(["2", "1"]).asData()
        dataStore.values[ResourcesWriter.Constants.storeCreationKey] = (Date().timeIntervalSince1970 - 31.days).asData()
        let core = PassthroughCoreMock(dataStore: dataStore)

        // When
        let writer = ResourcesWriter(core: core)
        XCTAssertNil(dataStore.values[ResourcesWriter.Constants.knownResourcesKey])

        // Then
        writer.write(resources: [.mockWith(identifier: "1")])
        XCTAssertEqual(core.events(ofType: EnrichedResource.self).count, 1)
        XCTAssertEqual(dataStore.values[ResourcesWriter.Constants.knownResourcesKey], Set(["1"]).asData())
    }

    func testWhenInitialized_itSetsUpDataStore() {
        // Given
        let dataStore = DataStoreMock()
        let core = PassthroughCoreMock(dataStore: dataStore)

        // When
        _ = ResourcesWriter(core: core)

        // Then
        XCTAssertNotNil(dataStore.values[ResourcesWriter.Constants.storeCreationKey])
        XCTAssertNil(dataStore.values[ResourcesWriter.Constants.knownResourcesKey])
    }
}
