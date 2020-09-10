//
//  ExampleTests.swift
//  ExampleTests
//
//  Created by Ignacio Bonafonte Arruga on 10/09/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

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
