/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal

class CoreRegistryTest: XCTestCase {
    func testRegistration() {
        let core = PassthroughCoreMock()
        CoreRegistry.register(default: core)
        XCTAssertTrue(CoreRegistry.default === core)

        let name: String = .mockRandom()
        CoreRegistry.register(core, named: name)
        XCTAssertTrue(CoreRegistry.instance(named: name) === core)

        CoreRegistry.unregisterDefault()
        XCTAssertTrue(CoreRegistry.default is NOPDatadogCore)
        CoreRegistry.unregisterInstance(named: name)
        XCTAssertTrue(CoreRegistry.instance(named: name) is NOPDatadogCore)
    }

    func testConcurrency() {
        let core = PassthroughCoreMock()

        callConcurrently(
            { CoreRegistry.register(default: core) },
            { _ = CoreRegistry.default },
            { CoreRegistry.unregisterDefault() },
            { CoreRegistry.register(core, named: "test") },
            { _ = CoreRegistry.instance(named: "test") },
            { CoreRegistry.unregisterInstance(named: "test") }
        )
    }
}
