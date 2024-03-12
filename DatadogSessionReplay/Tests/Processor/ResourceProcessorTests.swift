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
    var resources: [[EnrichedResource]] = []

    func write(resources: [EnrichedResource]) {
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
            [
                EnrichedResource(
                    identifier: resource1.calculateIdentifier(),
                    data: resource1.calculateData(),
                    context: context
                ),
                EnrichedResource(
                    identifier: resource2.calculateIdentifier(),
                    data: resource2.calculateData(),
                    context: context
                ),
            ]
        )
    }

    func testItDoesNotTryToWriteEmptyResources() {
        let writer = ResourceWriterMock()
        let processor = ResourceProcessor(
            queue: NoQueue(),
            resourcesWriter: writer
        )

        processor.process(resources: [], context: .mockRandom())

        XCTAssertTrue(writer.resources.isEmpty)
    }

    func testItRemovedDuplicates() {
        let writer = ResourceWriterMock()
        let processor = ResourceProcessor(
            queue: NoQueue(),
            resourcesWriter: writer
        )

        let resource1: MockResource = .mockRandom()
        let resource2: MockResource = .mockRandom()
        let context: EnrichedResource.Context = .mockRandom()

        processor.process(resources: [resource1, resource2], context: context)
        processor.process(resources: [resource1, resource2], context: context)

        XCTAssertEqual(writer.resources.count, 1)
        XCTAssertEqual(
            writer.resources[0],
            [
                EnrichedResource(
                    identifier: resource1.calculateIdentifier(),
                    data: resource1.calculateData(),
                    context: context
                ),
                EnrichedResource(
                    identifier: resource2.calculateIdentifier(),
                    data: resource2.calculateData(),
                    context: context
                ),
            ]
        )
    }
}
