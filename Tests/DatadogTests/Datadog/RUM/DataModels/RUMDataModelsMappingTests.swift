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
extension RUMErrorSource: RUMDataFormatConvertible {}
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

    func testRUMErrorSource() {
        verify(value: RUMErrorSource.custom, matches: .custom)
        verify(value: RUMErrorSource.source, matches: .source)
        verify(value: RUMErrorSource.network, matches: .network)
        verify(value: RUMErrorSource.webview, matches: .webview)
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
