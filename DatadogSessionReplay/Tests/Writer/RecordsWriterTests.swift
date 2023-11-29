/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogSessionReplay
@testable import TestUtilities

// swiftlint:disable empty_xctest_method
class RecordsWriterTests: XCTestCase {
    func testWhenFeatureScopeIsConnected_itWritesRecordsToCore() {
        // Given
        let core = PassthroughCoreMock()

        // When
        let writer = RecordsWriter(core: core)

        // Then
        writer.write(nextRecord: EnrichedRecord(context: .mockRandom(), records: .mockRandom()))
        writer.write(nextRecord: EnrichedRecord(context: .mockRandom(), records: .mockRandom()))
        writer.write(nextRecord: EnrichedRecord(context: .mockRandom(), records: .mockRandom()))

        XCTAssertEqual(core.events(ofType: EnrichedRecord.self).count, 3)
    }

    func testWhenFeatureScopeIsNotConnected_itDoesNotWriteRecordsToCore() throws {
        // Given
        let core = SingleFeatureCoreMock<MockFeature>()
        let feature = MockFeature()
        try core.register(feature: feature)

        // When
        let writer = RecordsWriter(core: core)

        // Then
        writer.write(nextRecord: EnrichedRecord(context: .mockRandom(), records: .mockRandom()))

        XCTAssertEqual(core.events(ofType: EnrichedRecord.self).count, 0)
    }

    func testWhenSucceedingRecordsDescribeDifferentRUMViews_itWritesThemToSeparateBatches() throws {
        // Given
        let forceNewBatchExpectation = expectation(description: "Should force new batch on view-id change")
        forceNewBatchExpectation.expectedFulfillmentCount = 2
        let core = PassthroughCoreMock(forceNewBatchExpectation: forceNewBatchExpectation)

        // When
        let writer = RecordsWriter(core: core)

        // Then
        writer.write(nextRecord: EnrichedRecord(context: .mockWith(rumContext: .mockWith(viewID: "view1")), records: .mockRandom()))
        writer.write(nextRecord: EnrichedRecord(context: .mockWith(rumContext: .mockWith(viewID: "view2")), records: .mockRandom()))

        XCTAssertEqual(core.events(ofType: EnrichedRecord.self).count, 2)
        waitForExpectations(timeout: 0.5, handler: nil)
    }
}
// swiftlint:enable empty_xctest_method
