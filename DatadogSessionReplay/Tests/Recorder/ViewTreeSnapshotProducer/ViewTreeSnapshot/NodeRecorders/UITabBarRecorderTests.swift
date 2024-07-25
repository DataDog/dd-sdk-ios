/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import TestUtilities

@_spi(Internal)
@testable import DatadogSessionReplay

class UITabBarRecorderTests: XCTestCase {
    private let recorder = UITabBarRecorder(identifier: UUID())

    func testWhenViewIsOfExpectedType() throws {
        // When
        let tabBar = UITabBar.mock(withFixture: .allCases.randomElement()!)
        let viewAttributes = ViewAttributes(frameInRootView: tabBar.frame, view: tabBar)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: tabBar, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)
        XCTAssertTrue(semantics.nodes.first?.wireframesBuilder is UITabBarWireframesBuilder)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: .mockAny(), in: .mockAny()))
    }

    func testWhenRecordingSubviewTwice() {
        // Given
        let tabBar = UITabBar.mock(withFixture: .visible(.someAppearance))
        tabBar.items = [UITabBarItem(title: "first", image: UIImage(), tag: 0)]
        let viewAttributes = ViewAttributes(frameInRootView: tabBar.frame, view: tabBar)

        // When
        let semantics1 = recorder.semantics(of: tabBar, with: viewAttributes, in: .mockAny())
        let semantics2 = recorder.semantics(of: tabBar, with: viewAttributes, in: .mockAny())

        let builder = SessionReplayWireframesBuilder()
        let wireframes1 = semantics1?.nodes.flatMap { $0.wireframesBuilder.buildWireframes(with: builder) }
        let wireframes2 = semantics2?.nodes.flatMap { $0.wireframesBuilder.buildWireframes(with: builder) }

        // Then
        DDAssertReflectionEqual(wireframes1, wireframes2)
    }
}
#endif
