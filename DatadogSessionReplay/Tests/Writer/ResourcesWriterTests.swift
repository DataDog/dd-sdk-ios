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

    func testWhenFeatureScopeIsConnected_itWritesResourcesToCore_andRemovesDuplicates() throws {
        // Given
        let dataStore = DataStoreMock()
        let core = PassthroughCoreMock(dataStore: dataStore)

        // When
        let writer = ResourcesWriter(core: core)

        // Then
        writer.write(resources: [.mockWith(identifier: "1")])
        writer.write(resources: [.mockWith(identifier: "1")])

        XCTAssertEqual(core.events(ofType: EnrichedResource.self).count, 1)
        let data = try XCTUnwrap(dataStore.values["processed-resources"])
        XCTAssertGreaterThan(data.count, 0)
    }

    func testWhenFeatureScopeIsConnected_itWritesResourcesToCore_andReadsKnownDuplicates() throws {
        // Given
        let dataStore = DataStoreMock()
        dataStore.values["processed-resources"] = try JSONEncoder().encode(Set(["1"]))
        let core = PassthroughCoreMock(dataStore: dataStore)

        // When
        let writer = ResourcesWriter(core: core)

        // Then
        writer.write(resources: [.mockWith(identifier: "1")])

        XCTAssertEqual(core.events(ofType: EnrichedResource.self).count, 0)
    }
}
