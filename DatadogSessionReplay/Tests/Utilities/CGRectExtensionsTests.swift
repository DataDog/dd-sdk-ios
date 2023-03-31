/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class CGRectExtensionsTests: XCTestCase {
    func testPutInside() {
        // Given
        let container = CGRect(x: 10, y: 20, width: 100, height: 200)
        let frame = CGRect(x: .mockRandom(), y: .mockRandom(), width: 40, height: 50)

        // When
        let insideLT = frame.putInside(container, horizontalAlignment: .left, verticalAlignment: .top)
        let insideRT = frame.putInside(container, horizontalAlignment: .right, verticalAlignment: .top)
        let insideCT = frame.putInside(container, horizontalAlignment: .center, verticalAlignment: .top)

        let insideLB = frame.putInside(container, horizontalAlignment: .left, verticalAlignment: .bottom)
        let insideRB = frame.putInside(container, horizontalAlignment: .right, verticalAlignment: .bottom)
        let insideCB = frame.putInside(container, horizontalAlignment: .center, verticalAlignment: .bottom)

        let insideLM = frame.putInside(container, horizontalAlignment: .left, verticalAlignment: .middle)
        let insideRM = frame.putInside(container, horizontalAlignment: .right, verticalAlignment: .middle)
        let insideCM = frame.putInside(container, horizontalAlignment: .center, verticalAlignment: .middle)

        // Then
        XCTAssertEqual(insideLT, .init(x: 10, y: 20, width: 40, height: 50))
        XCTAssertEqual(insideRT, .init(x: 70, y: 20, width: 40, height: 50))
        XCTAssertEqual(insideCT, .init(x: 40, y: 20, width: 40, height: 50))

        XCTAssertEqual(insideLB, .init(x: 10, y: 170, width: 40, height: 50))
        XCTAssertEqual(insideRB, .init(x: 70, y: 170, width: 40, height: 50))
        XCTAssertEqual(insideCB, .init(x: 40, y: 170, width: 40, height: 50))

        XCTAssertEqual(insideLM, .init(x: 10, y: 95, width: 40, height: 50))
        XCTAssertEqual(insideRM, .init(x: 70, y: 95, width: 40, height: 50))
        XCTAssertEqual(insideCM, .init(x: 40, y: 95, width: 40, height: 50))
    }
}
