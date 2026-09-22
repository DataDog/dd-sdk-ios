/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM
import TestUtilities

#if !os(watchOS)

#if canImport(SwiftUI)
import SwiftUI
#endif

#if os(macOS)
import AppKit
#endif

class UIKitRUMViewsPredicateTests: XCTestCase {
    #if os(macOS)
    func makePredicate() -> AppKitRUMViewsPredicate {
        DefaultAppKitRUMViewsPredicate()
    }
    #else
    func makePredicate() -> UIKitRUMViewsPredicate {
        DefaultUIKitRUMViewsPredicate()
    }
    #endif

    func testGivenDefaultPredicate_whenAskingForCustomSwiftViewController_itNamesTheViewByItsClassName() {
        // Given
        let predicate = makePredicate()

        // When
        let customViewController = createMockView(viewControllerClassName: "CustomSwiftViewController")
        let rumView = predicate.rumView(for: customViewController)

        // Then
        XCTAssertEqual(rumView?.name, "CustomSwiftViewController")
        XCTAssertEqual(rumView?.path, "CustomSwiftViewController")
        XCTAssertTrue(rumView!.attributes.isEmpty)
    }

    func testGivenDefaultPredicate_whenAskingForCustomObjcViewController_itNamesTheViewByItsClassName() {
        // Given
        let predicate = makePredicate()

        // When
        let customViewController = CustomObjcViewController()
        let rumView = predicate.rumView(for: customViewController)

        // Then
        XCTAssertEqual(rumView?.name, "CustomObjcViewController")
        XCTAssertEqual(rumView?.path, "CustomObjcViewController")
        XCTAssertTrue(rumView!.attributes.isEmpty)
    }

    func testGivenDefaultPredicate_whenAskingUIKitViewController_itReturnsNoView() {
        // Given
        let predicate = makePredicate()

        // When
        let uiKitViewController = DDViewController()
        let rumView = predicate.rumView(for: uiKitViewController)

        // Then
        XCTAssertNil(rumView)
    }

    #if os(macOS)
    private final class CustomCollectionViewItem: NSCollectionViewItem {}

    func testGivenDefaultPredicate_whenAskingForCollectionViewItemOrSubclass_itReturnsNoView() {
        // Given
        let predicate = makePredicate()

        // When
        let collectionViewItem = predicate.rumView(for: NSCollectionViewItem())
        let customCollectionViewItem = predicate.rumView(for: CustomCollectionViewItem())

        // Then
        XCTAssertNil(collectionViewItem)
        XCTAssertNil(customCollectionViewItem)
    }
    #endif

#if canImport(SwiftUI)
    func testGivenDefaultPredicate_whenAskingSwiftUIViewController_itReturnsNoView() {
        // Given
        let predicate = makePredicate()

        // When
        let swiftUIHostingController = DDHostingController<EmptyView>(rootView: EmptyView())
        let rumView = predicate.rumView(for: swiftUIHostingController)

        // Then
        XCTAssertNil(rumView)
    }
#endif
}

#endif
