/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogFlags

final class FlagsTests: XCTestCase {
    
    func testFlagsEnableMethod() {
        // Test that the enable method exists and can be called
        let configuration = FlagsConfiguration()
        
        // This should not crash - the method is currently a placeholder
        Flags.enable(with: configuration)
        
        // Since it's a TODO implementation, we just verify it doesn't crash
        XCTAssertTrue(true, "Flags.enable should not crash")
    }
    
    func testFlagsConfiguration() {
        // Test that FlagsConfiguration can be instantiated
        let configuration = FlagsConfiguration()
        
        XCTAssertNotNil(configuration)
    }
}
