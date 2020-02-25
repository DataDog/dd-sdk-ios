import XCTest

import HTTPServerMockTests

var tests = [XCTestCaseEntry]()
tests += HTTPServerMockTests.allTests()
XCTMain(tests)
