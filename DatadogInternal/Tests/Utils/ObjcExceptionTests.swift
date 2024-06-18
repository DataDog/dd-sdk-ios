/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal

class ObjcExceptionTests: XCTestCase {
    func testWrappedObjcException() {
        // Given
        ObjcException.rethrow = { _ in throw ErrorMock("objc exception") }
        defer { ObjcException.rethrow = { $0() } }

        do {
            #sourceLocation(file: "File.swift", line: 1)
            try objc_rethrow {}
            #sourceLocation()
            XCTFail("objc_rethrow should throw an error")
        } catch let exception as ObjcException {
            let error = exception.error as? ErrorMock
            XCTAssertEqual(error?.description, "objc exception")
            XCTAssertEqual(exception.file, "\(moduleName())/File.swift")
            XCTAssertEqual(exception.line, 1)
        } catch {
            XCTFail("error should be of type ObjcException")
        }
    }

    func testRethrowSwiftError() {
        do {
            try objc_rethrow { throw ErrorMock("swift error") }
            XCTFail("objc_rethrow should throw an error")
        } catch let error as ErrorMock {
            XCTAssertEqual(error.description, "swift error")
        } catch is ObjcException {
            XCTFail("error should not be of type ObjcException")
        } catch {
            XCTFail("error should be of type ErrorMock")
        }
    }
}
