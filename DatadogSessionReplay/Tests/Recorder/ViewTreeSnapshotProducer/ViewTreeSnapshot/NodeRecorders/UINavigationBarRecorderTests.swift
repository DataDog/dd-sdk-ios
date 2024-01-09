/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay

class UINavigationBarRecorderTests: XCTestCase {
    private let recorder = UINavigationBarRecorder()

    func testWhenViewIsOfExpectedType() throws {
        // Given
        let navigationBar = UINavigationBar.mock(withFixture: .allCases.randomElement()!)
        let viewAttributes = ViewAttributes(frameInRootView: navigationBar.frame, view: navigationBar)

        // When
        let semantics = try XCTUnwrap(recorder.semantics(of: navigationBar, with: viewAttributes, in: .mockAny()) as? SpecificElement)

        // Then
        XCTAssertEqual(semantics.subtreeStrategy, .record)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: .mockAny(), in: .mockAny()))
    }
}
