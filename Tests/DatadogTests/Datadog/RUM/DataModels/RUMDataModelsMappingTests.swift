/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private protocol RUMDataFormatConvertible {
    associatedtype DTOValue
    var toRUMDataFormat: DTOValue { get }
}

extension RUMHTTPMethod: RUMDataFormatConvertible {}
extension RUMResourceKind: RUMDataFormatConvertible {}
extension RUMInternalErrorSource: RUMDataFormatConvertible {}
extension RUMUserActionType: RUMDataFormatConvertible {}

class RUMDataModelsMappingTests: XCTestCase {
    func testInt() {
        XCTAssertEqual(Int.min.toInt64, Int64.min)
        XCTAssertEqual(Int(42).toInt64, 42)
        XCTAssertEqual(Int.max.toInt64, Int64.max)
    }

    func testUInt() {
        XCTAssertEqual(UInt.min.toInt64, 0)
        XCTAssertEqual(UInt(42).toInt64, 42)
        XCTAssertEqual(UInt.max.toInt64, Int64.max)
    }

    func testUInt64() {
        XCTAssertEqual(UInt64.min.toInt64, 0)
        XCTAssertEqual(UInt64(42).toInt64, 42)
        XCTAssertEqual(UInt64.max.toInt64, Int64.max)
    }

    func testRUMUUID() {
        let generator = DefaultRUMUUIDGenerator()

        (0...50).forEach { _ in
            XCTAssertValidRumUUID(generator.generateUnique().toRUMDataFormat)
        }
    }

    func testRUMHTTPMethod() {
        verify(value: RUMHTTPMethod.GET, matches: .methodGET)
        verify(value: RUMHTTPMethod.POST, matches: .post)
        verify(value: RUMHTTPMethod.PUT, matches: .put)
        verify(value: RUMHTTPMethod.DELETE, matches: .delete)
        verify(value: RUMHTTPMethod.HEAD, matches: .head)
        verify(value: RUMHTTPMethod.PATCH, matches: .patch)
    }

    func testRUMResourceKind() {
        verify(value: RUMResourceKind.image, matches: .image)
        verify(value: RUMResourceKind.xhr, matches: .xhr)
        verify(value: RUMResourceKind.beacon, matches: .beacon)
        verify(value: RUMResourceKind.css, matches: .css)
        verify(value: RUMResourceKind.document, matches: .document)
        verify(value: RUMResourceKind.fetch, matches: .fetch)
        verify(value: RUMResourceKind.font, matches: .font)
        verify(value: RUMResourceKind.js, matches: .js)
        verify(value: RUMResourceKind.media, matches: .media)
        verify(value: RUMResourceKind.other, matches: .other)
    }

    func testRUMInternalErrorSource() {
        func verifyInternalSource(_ internalSource: RUMInternalErrorSource) {
            let rumSource = internalSource.toRUMDataFormat
            switch internalSource {
            case .custom: XCTAssertEqual(rumSource, .custom)
            case .source: XCTAssertEqual(rumSource, .source)
            case .network: XCTAssertEqual(rumSource, .network)
            case .webview: XCTAssertEqual(rumSource, .webview)
            case .logger: XCTAssertEqual(rumSource, .logger)
            }
        }
        verifyInternalSource(.custom)
        verifyInternalSource(.source)
        verifyInternalSource(.network)
        verifyInternalSource(.webview)
        verifyInternalSource(.logger)
    }

    func testRUMUserActionType() {
        verify(value: RUMUserActionType.tap, matches: .tap)
        verify(value: RUMUserActionType.swipe, matches: .swipe)
        verify(value: RUMUserActionType.scroll, matches: .scroll)
        verify(value: RUMUserActionType.custom, matches: .custom)
    }

    // MARK: - Helpers

    private func verify<Value: RUMDataFormatConvertible, DTOValue: Equatable>(
        value: Value,
        matches dtoValue: DTOValue,
        line: UInt = #line
    ) where Value.DTOValue == DTOValue {
        XCTAssertEqual(value.toRUMDataFormat, dtoValue, line: line)
    }
}

class RUMInternalDataModelsMappingTests: XCTestCase {
    func testRUMErrorSourceToRUMInternalErrorSource() {
        func verifyErrorSource(_ errorSource: RUMErrorSource) {
            let internalSource = RUMInternalErrorSource(errorSource)
            switch errorSource { // if there is an unhandled case, won't compile
            case .custom: XCTAssertEqual(internalSource, .custom)
            case .network: XCTAssertEqual(internalSource, .network)
            case .source: XCTAssertEqual(internalSource, .source)
            case .webview: XCTAssertEqual(internalSource, .webview)
            }
        }
        // verify all known cases
        verifyErrorSource(.custom)
        verifyErrorSource(.network)
        verifyErrorSource(.source)
        verifyErrorSource(.webview)
    }
}
