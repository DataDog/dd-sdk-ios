/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@_spi(objc)
@testable import DatadogRUM

class DDSwiftUIRUMActionsPredicateTests: XCTestCase {
    func testGivenDefaultPredicate_whenAskingForComponentName_itReturnsAction() {
        // Given
        let predicate = objc_DefaultSwiftUIRUMActionsPredicate()

        // When
        let rumAction = predicate.rumAction(with: "Button")

        // Then
        XCTAssertEqual(rumAction?.name, "Button")
        XCTAssertTrue(rumAction!.attributes.isEmpty)
    }

    func testGivenPredicateWithLegacyEnabled_onAnyiOSVersion_itReturnsAction() {
        // Given
        let predicate = objc_DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true)

        // When
        let rumAction = predicate.rumAction(with: "SwiftUI_Action")

        // Then
        XCTAssertEqual(rumAction?.name, "SwiftUI_Action")
        XCTAssertTrue(rumAction!.attributes.isEmpty)
    }

    func testGivenPredicateWithLegacyDisabled_oniOS17_itReturnsNoAction() {
        // Given
        let predicate = objc_DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: false)

        // When
        let rumAction = predicate.rumAction(with: "SwiftUI_Action")

        // Then
        if #available(iOS 18.0, *) {
            XCTAssertEqual(rumAction?.name, "SwiftUI_Action")
            XCTAssertTrue(rumAction!.attributes.isEmpty)
        } else {
            XCTAssertNil(rumAction, "On iOS 17 and below with legacy disabled, should return `nil`")
        }
    }
}
