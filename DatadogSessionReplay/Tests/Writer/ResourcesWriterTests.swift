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

        XCTAssertEqual(core.events(ofType: [EnrichedResource].self).count, 3)
    }

    func testWhenFeatureScopeIsNotConnected_itDoesNotWriteRecordsToCore() throws {
        // Given
        let core = SingleFeatureCoreMock<SessionReplayFeature>()
        let feature = try SessionReplayFeature(
            core: core,
            configuration: .init(replaySampleRate: .mockAny())
        )
        try core.register(feature: feature)

        // When
        let writer = ResourcesWriter(core: core)

        // Then
        writer.write(resources: [.mockRandom()])

        XCTAssertEqual(core.events(ofType: EnrichedResource.self).count, 0)
    }
}
