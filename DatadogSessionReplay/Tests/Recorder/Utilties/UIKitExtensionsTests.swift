/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
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
}
