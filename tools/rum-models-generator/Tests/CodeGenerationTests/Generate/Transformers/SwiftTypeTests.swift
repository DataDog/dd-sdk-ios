/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
@testable import CodeGeneration

final class SwiftTypeTests: XCTestCase {
    func testSwiftStructProperty_mutabilityLevelOrder() {
        let immutable = SwiftStruct.Property.Mutability.immutable.rawValue
        let mutableInternally = SwiftStruct.Property.Mutability.mutableInternally.rawValue
        let mutable = SwiftStruct.Property.Mutability.mutable.rawValue

        // The level order of property mutability must always be
        // .immutable < .mutableInternally < .mutable
        XCTAssertTrue(immutable < mutableInternally)
        XCTAssertTrue(mutableInternally < mutable)
    }
}
