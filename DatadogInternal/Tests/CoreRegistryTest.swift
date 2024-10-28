/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import TestUtilities

@testable import DatadogInternal

class CoreRegistryTest: XCTestCase {
    func testRegistration() {
        let core = PassthroughCoreMock()
        CoreRegistry.register(default: core)
        XCTAssertTrue(CoreRegistry.default === core)

        let name: String = .mockRandom()
        CoreRegistry.register(core, named: name)
        XCTAssertTrue(CoreRegistry.instance(named: name) === core)
        XCTAssertTrue(CoreRegistry.isRegistered(instanceName: CoreRegistry.defaultInstanceName))
        XCTAssertTrue(CoreRegistry.isRegistered(instanceName: name))

        CoreRegistry.unregisterDefault()
        CoreRegistry.unregisterInstance(named: name)
        XCTAssertTrue(CoreRegistry.default is NOPDatadogCore)
        XCTAssertTrue(CoreRegistry.instance(named: name) is NOPDatadogCore)
        XCTAssertFalse(CoreRegistry.isRegistered(instanceName: CoreRegistry.defaultInstanceName))
        XCTAssertFalse(CoreRegistry.isRegistered(instanceName: name))
    }

    func testConcurrency() {
        let core = PassthroughCoreMock()

        // swiftlint:disable opening_brace
        callConcurrently(
            { CoreRegistry.register(default: core) },
            { _ = CoreRegistry.default },
            { CoreRegistry.unregisterDefault() },
            { CoreRegistry.register(core, named: "test") },
            { _ = CoreRegistry.instance(named: "test") },
            { CoreRegistry.unregisterInstance(named: "test") }
        )
        // swiftlint:enable opening_brace

        CoreRegistry.unregisterDefault()
        CoreRegistry.unregisterInstance(named: "test")
    }

    func testIsFeatureEnabled_whenFeatureIsRegistered_itReturnsTrue() {
        // Given
        let core = FeatureRegistrationCoreMock()
        let feature = MockFeature()

        // Register the mock feature in the core
        try? core.register(feature: feature)

        // Register the core in the CoreRegistry
        CoreRegistry.register(default: core)

        // When
        let isEnabled = CoreRegistry.isFeatureEnabled(feature: MockFeature.self)

        // Then
        XCTAssertTrue(isEnabled)

        // Cleanup
        CoreRegistry.unregisterDefault()
    }

    func testIsFeatureEnabled_whenFeatureIsNotRegistered_itReturnsFalse() {
        // Given
        let core = FeatureRegistrationCoreMock()

        // No feature registered

        // Register the core in the CoreRegistry
        CoreRegistry.register(default: core)

        // When
        let isEnabled = CoreRegistry.isFeatureEnabled(feature: MockFeature.self)

        // Then
        XCTAssertFalse(isEnabled)

        // Cleanup
        CoreRegistry.unregisterDefault()
    }
}
