/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@_spi(Internal)
@testable import DatadogSessionReplay

private class ResourceWriterMock: ResourcesWriting {
    var resources: [Set<EnrichedResource>] = []

    func write(resources: Set<EnrichedResource>) {
        self.resources.append(resources)
    }
}

class ResourceProcessorTests: XCTestCase {
    func testItWritesResources() {
        let writer = ResourceWriterMock()
        let processor = ResourceProcessor(
            queue: NoQueue(),
            resourcesWriter: writer
        )

        let resource1: MockResource = .mockRandom()
        let resource2: MockResource = .mockRandom()
        let context: EnrichedResource.Context = .mockRandom()

        processor.process(resources: [resource1, resource2], context: context)

        XCTAssertEqual(writer.resources.count, 1)
        XCTAssertEqual(
            writer.resources[0],
            Set([
                EnrichedResource(resource: resource1, context: context),
                EnrichedResource(resource: resource2, context: context)
            ])
        )
    }

    func testItRemovesDuplicateResources() {
        let writer = ResourceWriterMock()
        let processor = ResourceProcessor(
            queue: NoQueue(),
            resourcesWriter: writer
        )

        let resource: MockResource = .mockRandom()
        let context: EnrichedResource.Context = .mockRandom()

        processor.process(resources: [resource, resource], context: context)

        XCTAssertEqual(writer.resources.count, 1)
        XCTAssertEqual(
            writer.resources[0],
            Set([
                EnrichedResource(resource: resource, context: context)
            ])
        )
    }
}
