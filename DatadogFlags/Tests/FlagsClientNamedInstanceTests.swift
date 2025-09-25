/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogFlags

final class FlagsClientNamedInstanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clean up registry before each test
        for instanceName in FlagsClientRegistry.registeredInstanceNames() {
            FlagsClientRegistry.unregisterInstance(named: instanceName)
        }
    }

    override func tearDown() {
        // Clean up registry after each test
        for instanceName in FlagsClientRegistry.registeredInstanceNames() {
            FlagsClientRegistry.unregisterInstance(named: instanceName)
        }
        super.tearDown()
    }

    func testCreateWithNameOnly() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        let client = FlagsClient.create(name: "test-client", in: core)
        XCTAssertFalse(client is NOPFlagsClient, "Should create a functional client")

        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "test-client"))

        let retrieved = FlagsClientRegistry.instance(named: "test-client")
        XCTAssertTrue(retrieved === client, "Should register and retrieve the same instance")
    }

    func testCreateWithConfiguration() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        let config = FlagsClient.Configuration(
            baseURL: "https://custom.endpoint.com",
            customHeaders: ["X-Custom": "value"],
            flaggingProxy: "proxy.example.com"
        )

        let client = FlagsClient.create(with: config, name: "configured-client", in: core)
        XCTAssertFalse(client is NOPFlagsClient, "Should create a functional client")

        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "configured-client"))

        let retrieved = FlagsClientRegistry.instance(named: "configured-client")
        XCTAssertTrue(retrieved === client, "Should register and retrieve the same instance")
    }

    func testInstanceRetrieval() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // Create multiple named instances
        let client1 = FlagsClient.create(name: "client1", in: core)
        let client2 = FlagsClient.create(name: "client2", in: core)
        let client3 = FlagsClient.create(name: "client3", in: core)

        // Verify each can be retrieved correctly
        XCTAssertTrue(FlagsClient.instance(named: "client1") === client1)
        XCTAssertTrue(FlagsClient.instance(named: "client2") === client2)
        XCTAssertTrue(FlagsClient.instance(named: "client3") === client3)

        // Non-existent instance should return NOP
        let nonExistent = FlagsClient.instance(named: "nonexistent")
        XCTAssertTrue(nonExistent is NOPFlagsClient)
    }

    func testCreateFailureReturnsNOP() {
        let core = FeatureRegistrationCoreMock()
        // Don't enable Flags feature - should cause creation to fail

        let client = FlagsClient.create(name: "failing-client", in: core)
        XCTAssertTrue(client is NOPFlagsClient, "Should return NOPFlagsClient when creation fails")

        XCTAssertFalse(FlagsClientRegistry.isRegistered(instanceName: "failing-client"))
    }

    func testStorageIsolation() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        let client1 = FlagsClient.create(name: "isolated1", in: core)
        let client2 = FlagsClient.create(name: "isolated2", in: core)

        // Verify clients have different instance names for storage isolation
        XCTAssertNotNil(client1, "Client 1 should be created")
        XCTAssertNotNil(client2, "Client 2 should be created")

        // Verify they are registered separately
        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "isolated1"))
        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "isolated2"))

        // Verify we can retrieve them independently
        let retrieved1 = FlagsClient.instance(named: "isolated1")
        let retrieved2 = FlagsClient.instance(named: "isolated2")

        XCTAssertTrue(retrieved1 === client1, "Should retrieve correct client 1")
        XCTAssertTrue(retrieved2 === client2, "Should retrieve correct client 2")

        // Verify they operate independently - should return different defaults
        let boolValue1 = client1.getBooleanValue(key: "test-flag", defaultValue: false)
        let boolValue2 = client2.getBooleanValue(key: "test-flag", defaultValue: true)

        // Should return their respective defaults since no flags are set
        XCTAssertFalse(boolValue1)
        XCTAssertTrue(boolValue2)
    }

    func testDuplicateNameHandling() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        let client1 = FlagsClient.create(name: "duplicate", in: core)
        let client2 = FlagsClient.create(name: "duplicate", in: core)

        // First client should be registered
        XCTAssertTrue(FlagsClientRegistry.instance(named: "duplicate") === client1)

        // Second client with same name should have been ignored during registration
        // But the creation itself should still return a functional client
        XCTAssertFalse(client2 is NOPFlagsClient, "Client creation should succeed")
        XCTAssertFalse(FlagsClientRegistry.instance(named: "duplicate") === client2, "Should not replace existing registration")
    }

    func testMultipleInstancesWithDifferentConfigurations() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        let config1 = FlagsClient.Configuration(baseURL: "https://endpoint1.com")
        let config2 = FlagsClient.Configuration(baseURL: "https://endpoint2.com")

        _ = FlagsClient.create(with: config1, name: "endpoint1", in: core)
        _ = FlagsClient.create(with: config2, name: "endpoint2", in: core)
        _ = FlagsClient.create(name: "default-config", in: core)

        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "endpoint1"))
        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "endpoint2"))
        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "default-config"))

        XCTAssertEqual(FlagsClientRegistry.registeredInstanceNames().count, 3)
    }

    func testCreateWithOptionalName() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // Test create without name - should use "main" as default
        let client1 = FlagsClient.create(in: core)
        XCTAssertFalse(client1 is NOPFlagsClient, "Should create a functional client")
        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "main"))

        let retrieved = FlagsClient.default
        XCTAssertTrue(retrieved === client1, "Default client should be retrievable")

        // Test create with config but no name - should also use "main"
        let config = FlagsClient.Configuration(baseURL: "https://custom.endpoint.com")
        let client2 = FlagsClient.create(with: config, in: core)

        // This should silently fail (second registration to "main") 
        XCTAssertFalse(client2 is NOPFlagsClient, "Client creation should succeed")
        XCTAssertTrue(FlagsClient.default === client1, "Default should remain the first client")
    }

    func testDefaultClientAccess() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // Before creating any client, default should be NOP
        let defaultBefore = FlagsClient.default
        XCTAssertTrue(defaultBefore is NOPFlagsClient, "Should return NOP when no default exists")

        // Create a default client
        let client = FlagsClient.create(in: core)
        let defaultAfter = FlagsClient.default
        XCTAssertTrue(defaultAfter === client, "Should return the created default client")
        XCTAssertFalse(defaultAfter is NOPFlagsClient, "Should not be NOP after creation")
    }
}
