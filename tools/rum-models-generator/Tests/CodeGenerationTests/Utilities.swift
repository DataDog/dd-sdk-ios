/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import Difference
import XCTest
@testable import CodeGeneration

public func XCTAssertEqual<T: Equatable>(
    _ expected: T,
    _ received: T,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(
        expected == received,
        "Found difference for \n" + diff(expected, received).joined(separator: ", "),
        file: file,
        line: line
    )
}

public func XCTAssertEqual(
    _ expected: [SwiftType],
    _ received: [SwiftType],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(expected.count, received.count, "Received different number of elements than expected.", file: file, line: line)
    zip(expected, received).forEach { expected, received in
        if let expected = expected as? SwiftStruct, let received = received as? SwiftStruct {
            XCTAssertEqual(expected, received, file: file, line: line)
        } else if let expected = expected as? SwiftEnum, let received = received as? SwiftEnum {
            XCTAssertEqual(expected, received, file: file, line: line)
        } else {
            XCTFail("Expected \(type(of: expected)), but received \(type(of: received))", file: file, line: line)
        }
    }
}
