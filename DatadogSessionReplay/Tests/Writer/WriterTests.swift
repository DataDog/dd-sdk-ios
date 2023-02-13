/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Datadog
@testable import DatadogSessionReplay
@testable import TestUtilities

// swiftlint:disable empty_xctest_method
class WriterTests: XCTestCase {
    func testWhenFeatureScopeIsConnected_itWritesRecordsToCore() {
        // Given
        let core = PassthroughCoreMock()
        let writer = Writer()

        // When
        writer.startWriting(to: core)

        // Then
        writer.write(nextRecord: EnrichedRecord(rumContext: .mockRandom(), records: .mockRandom()))
        writer.write(nextRecord: EnrichedRecord(rumContext: .mockRandom(), records: .mockRandom()))
        writer.write(nextRecord: EnrichedRecord(rumContext: .mockRandom(), records: .mockRandom()))

        XCTAssertEqual(core.events(ofType: EnrichedRecord.self).count, 3)
    }

    func testWhenFeatureScopeIsNotConnected_itDoesNotWriteRecordsToCore() {
        // TODO: RUMM-2690
        // Implementing this test requires creating mocks for `DatadogContext` (passed in `FeatureScope`),
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }

    func testWhenSucceedingRecordsDescribeDifferentRUMViews_itWritesThemToSeparateBatches() {
        // TODO: RUMM-2690
        // Implementing this test requires creating mocks for `DatadogContext` (passed in `FeatureScope`),
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }
}
// swiftlint:enable empty_xctest_method
