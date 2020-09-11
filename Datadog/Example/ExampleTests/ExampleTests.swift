/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Example


class ExampleTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExampleSuccess() throws {
        XCTAssert(true)
    }

    func testExampleError() throws {
        XCTAssert(false)
    }

//    func testExampleCrash() throws {
//        [][0]
//    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            DebugLoggingViewController.accessibilityActivate()
        }
    }

}
