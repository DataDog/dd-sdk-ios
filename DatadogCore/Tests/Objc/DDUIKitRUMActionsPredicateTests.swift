/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(objc)
import DatadogRUM

#if canImport(SwiftUI)
import SwiftUI
#endif

class DDUIKitRUMActionsPredicateTests: XCTestCase {
    func testGivenDefaultPredicate_whenAskingForCustomView_itNamesTheActionByItsClassName() {
        // Given
        let predicate = objc_DefaultUIKitRUMActionsPredicate()

        // When
        #if os(tvOS)
        let rumAction = predicate.rumAction(press: .select, targetView: UIButton())
        #else
        let rumAction = predicate.rumAction(targetView: UIButton())
        #endif
        // Then
        XCTAssertEqual(rumAction?.name, "UIButton")
        XCTAssertTrue(rumAction!.attributes.isEmpty)
    }

    func testGivenDefaultPredicate_whenAskingForViewWithAccesiblityIdentifier_itNamesTheActionWithIt() {
        // Given
        let predicate = objc_DefaultUIKitRUMActionsPredicate()
        let targetView = UIButton()
        targetView.accessibilityIdentifier = "Identifier"

        // When
        #if os(tvOS)
        let rumAction = predicate.rumAction(press: .select, targetView: targetView)
        #else
        let rumAction = predicate.rumAction(targetView: targetView)
        #endif

        // Then
        XCTAssertEqual(rumAction?.name, "UIButton(Identifier)")
        XCTAssertTrue(rumAction!.attributes.isEmpty)
    }

#if canImport(SwiftUI)
    func testGivenDefaultPredicate_whenAskingSwiftUIView_itReturnsAction() {
        guard #available(iOS 13, tvOS 13, *) else {
            return
        }
        // Given
        let predicate = objc_DefaultUIKitRUMActionsPredicate()

        // When
        let swiftUIView = UIHostingController(rootView: EmptyView()).view!
        #if os(tvOS)
        let rumAction = predicate.rumAction(press: .select, targetView: swiftUIView)
        #else
        let rumAction = predicate.rumAction(targetView: swiftUIView)
        #endif

        // Then
        XCTAssertNotNil(rumAction)
    }
#endif
}
