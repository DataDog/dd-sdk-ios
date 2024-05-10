/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import XCTest
@testable import DatadogSessionReplay

class CFTypeSafetyTests: XCTestCase {
    func testInvalidCGColorValueIsSanitized() {
        let valid: CGColor = UIColor.red.cgColor
        XCTAssertEqual(valid, valid.safeCast)

        let string: Any = "invalid CGColor value"
        let invalid = string as! CGColor
        XCTAssertNil(invalid.safeCast)
    }
}
#endif
