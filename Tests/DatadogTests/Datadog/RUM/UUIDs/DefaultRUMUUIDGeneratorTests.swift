/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DefaultRUMUUIDGeneratorTests: XCTestCase {
    /// Tests UUIDs conformance to rum-events-format regexp:
    /// https://github.com/DataDog/rum-events-format/blob/master/schemas/_common-schema.json
    func testUUIDsAreRepresesntedAsValidRUMString() {
        let generator = DefaultRUMUUIDGenerator()

        (0...50).forEach { _ in
            XCTAssertValidRumUUID(generator.generateUnique().toString)
        }
    }
}
