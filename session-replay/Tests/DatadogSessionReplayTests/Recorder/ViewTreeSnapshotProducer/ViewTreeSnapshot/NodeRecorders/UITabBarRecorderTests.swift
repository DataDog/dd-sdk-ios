/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class UITabBarRecorderTests: XCTestCase {
    private let recorder = UITabBarRecorder()

    func testWhenViewIsOfExpectedType() throws {
        // Given
        let tabBar = UITabBar.mock(withFixture: .allCases.randomElement()!)
        let viewAttributes = ViewAttributes(frameInRootView: tabBar.frame, view: tabBar)

        // When
        let semantics = try XCTUnwrap(recorder.semantics(of: tabBar, with: viewAttributes, in: .mockAny()) as? SpecificElement)

        // Then
        XCTAssertTrue(semantics.recordSubtree, "Tab Bar's subtree should be recorded")
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: .mockAny(), in: .mockAny()))
    }
}
