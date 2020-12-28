/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation
import Difference
import XCTest

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
