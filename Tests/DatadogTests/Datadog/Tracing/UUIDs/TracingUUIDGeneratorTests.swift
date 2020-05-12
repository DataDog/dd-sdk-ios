/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TracingUUIDGeneratorTests: XCTestCase {
    func testUUIDGenerationIsThreadSafe() {
        let generator = DefaultTracingUUIDGenerator()
        var generatedUUIDs: [TracingUUID] = []
        let queue = DispatchQueue(label: "uuid-array-sync")

        DispatchQueue.concurrentPerform(iterations: 1_000) { iteration in
            let uuid = generator.generateUnique()
            queue.async { generatedUUIDs.append(uuid) }
        }

        queue.sync { } // wait for all UUIDs in the array

        XCTAssertEqual(generatedUUIDs.count, 1_000)
    }
}
