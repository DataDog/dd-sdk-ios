/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogFlags

final class FlagsClientRegistryTests: XCTestCase {
    
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
    
    func testDefaultInstance() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)
        
        let client = FlagsClient.create(name: "main", in: core)
        FlagsClientRegistry.register(default: client)
        
        let defaultClient = FlagsClientRegistry.default
        XCTAssertTrue(defaultClient === client, "Default instance should return the registered client")
        
        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "main"))
    }
    
    func testDefaultInstanceNameConstant() {
        XCTAssertEqual(FlagsClientRegistry.defaultInstanceName, "main")
    }
    
    func testRegisterNamed() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)
        
        let client1 = FlagsClient.create(name: "test1", in: core)
        let client2 = FlagsClient.create(name: "test2", in: core)
        
        FlagsClientRegistry.register(client1, named: "test1")
        FlagsClientRegistry.register(client2, named: "test2")
        
        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "test1"))
        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "test2"))
        XCTAssertFalse(FlagsClientRegistry.isRegistered(instanceName: "nonexistent"))
        
        let retrieved1 = FlagsClientRegistry.instance(named: "test1")
        let retrieved2 = FlagsClientRegistry.instance(named: "test2")
        
        XCTAssertTrue(retrieved1 === client1, "Should retrieve correct client instance")
        XCTAssertTrue(retrieved2 === client2, "Should retrieve correct client instance")
    }
    
    func testRegisterDuplicateName() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)
        
        let client1 = FlagsClient.create(name: "duplicate", in: core)
        let client2 = FlagsClient.create(name: "duplicate", in: core)
        
        FlagsClientRegistry.register(client1, named: "duplicate")
        FlagsClientRegistry.register(client2, named: "duplicate") // Should be ignored
        
        let retrieved = FlagsClientRegistry.instance(named: "duplicate")
        XCTAssertTrue(retrieved === client1, "Should keep the first registered client")
    }
    
    func testInstanceNotFoundReturnsNOP() {
        let retrieved = FlagsClientRegistry.instance(named: "nonexistent")
        XCTAssertTrue(retrieved is NOPFlagsClient, "Should return NOPFlagsClient for non-existent instance")
    }
    
    func testDefaultNotRegisteredReturnsNOP() {
        let defaultClient = FlagsClientRegistry.default
        XCTAssertTrue(defaultClient is NOPFlagsClient, "Should return NOPFlagsClient when default is not registered")
    }
    
    func testUnregisterInstance() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)
        
        let client = FlagsClient.create(name: "test", in: core)
        FlagsClientRegistry.register(client, named: "test")
        
        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "test"))
        
        let unregistered = FlagsClientRegistry.unregisterInstance(named: "test")
        XCTAssertTrue(unregistered === client, "Should return the unregistered client")
        XCTAssertFalse(FlagsClientRegistry.isRegistered(instanceName: "test"))
        
        let retrieved = FlagsClientRegistry.instance(named: "test")
        XCTAssertTrue(retrieved is NOPFlagsClient, "Should return NOP after unregistering")
    }
    
    func testUnregisterDefault() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)
        
        let client = FlagsClient.create(name: "main", in: core)
        FlagsClientRegistry.register(default: client)
        
        XCTAssertTrue(FlagsClientRegistry.isRegistered(instanceName: "main"))
        
        let unregistered = FlagsClientRegistry.unregisterDefault()
        XCTAssertTrue(unregistered === client, "Should return the unregistered default client")
        XCTAssertFalse(FlagsClientRegistry.isRegistered(instanceName: "main"))
        
        let defaultClient = FlagsClientRegistry.default
        XCTAssertTrue(defaultClient is NOPFlagsClient, "Should return NOP after unregistering default")
    }
    
    func testUnregisterNonExistentReturnsNil() {
        let result = FlagsClientRegistry.unregisterInstance(named: "nonexistent")
        XCTAssertNil(result, "Should return nil when unregistering non-existent instance")
    }
    
    func testRegisteredInstanceNames() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)
        
        XCTAssertTrue(FlagsClientRegistry.registeredInstanceNames().isEmpty)
        
        let client1 = FlagsClient.create(name: "test1", in: core)
        let client2 = FlagsClient.create(name: "test2", in: core)
        
        FlagsClientRegistry.register(client1, named: "test1")
        FlagsClientRegistry.register(client2, named: "test2")
        
        let instanceNames = Set(FlagsClientRegistry.registeredInstanceNames())
        XCTAssertEqual(instanceNames, Set(["test1", "test2"]))
    }
    
    func testThreadSafety() {
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)
        
        let expectation = self.expectation(description: "Thread safety test")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        
        for i in 0..<10 {
            queue.async {
                let client = FlagsClient.create(name: "test\(i)", in: core)
                FlagsClientRegistry.register(client, named: "test\(i)")
                
                let retrieved = FlagsClientRegistry.instance(named: "test\(i)")
                XCTAssertTrue(retrieved === client)
                
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5.0, handler: nil)
        
        XCTAssertEqual(FlagsClientRegistry.registeredInstanceNames().count, 10)
    }
}