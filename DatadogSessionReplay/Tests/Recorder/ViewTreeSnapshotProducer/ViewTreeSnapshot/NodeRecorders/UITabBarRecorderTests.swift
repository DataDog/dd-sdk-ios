/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay

class UITabBarRecorderTests: XCTestCase {
    private let recorder = UITabBarRecorder()

    func testWhenViewIsOfExpectedType() throws {
        // When
        let tabBar = UITabBar.mock(withFixture: .allCases.randomElement()!)
        let viewAttributes = ViewAttributes(frameInRootView: tabBar.frame, view: tabBar)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: tabBar, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .record)
        XCTAssertTrue(semantics.nodes.first?.wireframesBuilder is UITabBarWireframesBuilder)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: .mockAny(), in: .mockAny()))
    }
}
