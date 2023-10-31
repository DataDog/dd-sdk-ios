/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
@testable import DatadogRUM

class RUMViewIdentityTests: XCTestCase {
    // MARK: - Comparing identifiables

    func testGivenTwoUIViewControllers_whenComparingTheirRUMViewIdentity_itEqualsOnlyForTheSameInstance() {
        // Given
        let vc1 = createMockView(viewControllerClassName: .mockRandom(among: .alphanumerics))
        let vc2 = createMockView(viewControllerClassName: .mockRandom(among: .alphanumerics))
        let vc3: UIViewController? = nil

        // When
        let identity1 = vc1.asRUMViewIdentity()
        let identity2 = vc2.asRUMViewIdentity()

        // Then
        XCTAssertTrue(identity1.equals(vc1))
        XCTAssertTrue(identity2.equals(vc2))
        XCTAssertTrue(identity1.equals(identity1))
        XCTAssertFalse(identity1.equals(vc2))
        XCTAssertFalse(identity2.equals(vc1))
        XCTAssertFalse(identity1.equals(identity2))
        XCTAssertFalse(identity1.equals(vc3))
    }

    func testGivenTwoStringKeys_whenComparingTheirRUMViewIdentity_itEqualsOnlyForTheSameInstance() {
        // Given
        let key1: String = .mockRandom()
        let key2: String = .mockRandom()
        let key3: String? = nil

        // When
        let identity1 = key1.asRUMViewIdentity()
        let identity2 = key2.asRUMViewIdentity()

        // Then
        XCTAssertTrue(identity1.equals(key1))
        XCTAssertTrue(identity2.equals(key2))
        XCTAssertTrue(identity1.equals(identity1))
        XCTAssertFalse(identity1.equals(key2))
        XCTAssertFalse(identity2.equals(key1))
        XCTAssertFalse(identity1.equals(identity2))
        XCTAssertFalse(identity1.equals(key3))
    }

    func testGivenTwoRUMViewIdentitiesOfDifferentKind_whenComparing_theyDoNotEqual() {
        // Given
        let vc = createMockView(viewControllerClassName: .mockRandom(among: .alphanumerics))
        let key: String = .mockRandom()

        // When
        let identity1 = vc.asRUMViewIdentity()
        let identity2 = key.asRUMViewIdentity()

        // Then
        XCTAssertFalse(identity1.equals(key))
        XCTAssertFalse(identity2.equals(vc))
    }

    // MARK: - Retrieving properties

    func testItReturnsDefaultViewPath() {
        let vc = createMockView(viewControllerClassName: "SomeViewController")
        let key = "SomeKey"

        XCTAssertEqual(vc.defaultViewPath, "SomeViewController")
        XCTAssertEqual(key.defaultViewPath, "SomeKey")
    }

    func testItReturnsManagedIdentifiable() {
        let vc = createMockView(viewControllerClassName: "SomeViewController")
        let key = "SomeKey"

        let identity1 = vc.asRUMViewIdentity()
        let identity2 = key.asRUMViewIdentity()

        XCTAssertTrue(identity1.isIdentifiable)
        XCTAssertTrue(identity2.isIdentifiable)
    }

    // MARK: - Memory management

    func testItStoresWeakReferenceToUIViewController() throws {
        var identity: RUMViewIdentity! // swiftlint:disable:this implicitly_unwrapped_optional

        try autoreleasepool {
            var vc: UIViewController? = UIViewController()
            identity = try XCTUnwrap(vc?.asRUMViewIdentity())
            XCTAssertTrue(identity.isIdentifiable, "Reference should be available while `vc` is alive.")
            vc = nil
        }

        XCTAssertFalse(identity.isIdentifiable, "Reference should not be available after `vc` was deallocated.")
    }
}
