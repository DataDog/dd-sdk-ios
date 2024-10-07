/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay

class UINavigationBarRecorderTests: XCTestCase {
    private let recorder = UINavigationBarRecorder(identifier: UUID())

    func testWhenViewIsOfExpectedType() throws {
        // Given
        let fixtures: [ViewAttributes.Fixture] = [
            .visible(.noAppearance),
            .visible(.someAppearance),
            .opaque
        ]

        let navigationBar = UINavigationBar.mock(withFixture: fixtures.randomElement()!)
        let viewAttributes = ViewAttributes(frameInRootView: navigationBar.frame, view: navigationBar, overrides: .mockAny())

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
#endif
