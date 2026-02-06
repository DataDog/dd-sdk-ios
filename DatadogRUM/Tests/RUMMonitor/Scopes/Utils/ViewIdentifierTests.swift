/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import TestUtilities
import XCTest
import UIKit

@testable import DatadogRUM

class ViewIdentifierTests: XCTestCase {
    // MARK: - Comparing identifiables

    func testGivenTwoStringKeys_whenComparingTheirRUMViewIdentity_itEqualsOnlyForTheSameInstance() {
        // Given
        let key1: String = .mockRandom()
        let key2: String = .mockRandom()

        // When
        let identity1 = ViewIdentifier(key1)
        let identity2 = ViewIdentifier(key2)

        // Then
        XCTAssertTrue(identity1 == ViewIdentifier(key1))
        XCTAssertTrue(identity2 == ViewIdentifier(key2))
        XCTAssertFalse(identity1 == identity2)
    }

    #if !os(watchOS)
    func testGivenTwoUIViewControllers_whenComparingTheirRUMViewIdentity_itEqualsOnlyForTheSameInstance() {
        // Given
        let vc1 = createMockView(viewControllerClassName: .mockRandom(among: .alphanumerics))
        let vc2 = createMockView(viewControllerClassName: .mockRandom(among: .alphanumerics))

        // When
        let identity1 = ViewIdentifier(vc1)
        let identity2 = ViewIdentifier(vc2)

        // Then
        XCTAssertTrue(identity1 == ViewIdentifier(vc1))
        XCTAssertTrue(identity2 == ViewIdentifier(vc2))
        XCTAssertFalse(identity1 == identity2)
    }

    func testGivenTwoRUMViewIdentitiesOfDifferentKind_whenComparing_theyDoNotEqual() {
        // Given
        let vc = createMockView(viewControllerClassName: .mockRandom(among: .alphanumerics))
        let key: String = .mockRandom()

        // When
        let identity1 = ViewIdentifier(vc)
        let identity2 = ViewIdentifier(key)

        // Then
        XCTAssertFalse(identity1 == identity2)
    }
    #endif
}

