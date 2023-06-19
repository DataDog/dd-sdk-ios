/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import TestUtilities
@testable import DatadogSessionReplay

class UIKitExtensionsTests: XCTestCase {
    func testUsesDarkMode() {
        // Given
        let lightView = UIView.mock(withFixture: .visible(.someAppearance))
        let darkView = UIView.mock(withFixture: .visible(.someAppearance))

        if #available(iOS 13.0, *) {
            // When
            lightView.overrideUserInterfaceStyle = [.light, .unspecified].randomElement()!
            darkView.overrideUserInterfaceStyle = .dark

            // Then
            XCTAssertFalse(lightView.usesDarkMode)
            XCTAssertTrue(darkView.usesDarkMode)
        } else {
            XCTAssertFalse(lightView.usesDarkMode)
            XCTAssertFalse(darkView.usesDarkMode)
        }
    }

    // swiftlint:disable opening_brace
    func testIsSensitiveText() {
       class Mock: NSObject, UITextInputTraits {
            var isSecureTextEntry = false
            var textContentType: UITextContentType! = nil // swiftlint:disable:this implicitly_unwrapped_optional
        }

        // Given
        let sensitiveTextMock = Mock()
        let nonSensitiveTextMock = Mock()
        let nonSensitiveContentTypes = UITextContentType.allCases.subtracting(sensitiveContentTypes)

        // When
        oneOrMoreOf([
            { sensitiveTextMock.isSecureTextEntry = true },
            { sensitiveTextMock.textContentType = sensitiveContentTypes.randomElement() },
        ])
        oneOrMoreOf([
            { nonSensitiveTextMock.isSecureTextEntry = false },
            { nonSensitiveTextMock.textContentType = nil },
            { nonSensitiveTextMock.textContentType = nonSensitiveContentTypes.randomElement() },
        ])

        // Then
        XCTAssertTrue(sensitiveTextMock.isSensitiveText)
        XCTAssertFalse(nonSensitiveTextMock.isSensitiveText)
    }
    // swiftlint:enable opening_brace
}
