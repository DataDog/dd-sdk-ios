/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
@testable import DatadogRUM
@testable import DatadogInternal

class CustomSwiftViewController: UIViewController {}

class UIKitExtensionsTests: XCTestCase {
    func testViewControllerCanonicalClassName() {
        let swiftViewController = CustomSwiftViewController()
        let objcViewController = CustomObjcViewController()

        XCTAssertEqual(swiftViewController.canonicalClassName, "DatadogCoreTests.CustomSwiftViewController")
        XCTAssertEqual(objcViewController.canonicalClassName, "CustomObjcViewController")
    }

    func testBundleIsUIKit() {
        let someUIKitClasses: [AnyClass] = [
            UIViewController.self,
            UIButton.self,
            UINavigationBar.self,
            UIScrollView.self
        ]

        let someNonUIKitClasses: [AnyClass] = [
            CustomSwiftViewController.self,
            CustomObjcViewController.self,
            OperationQueue.self,
        ]

        someUIKitClasses.forEach { XCTAssertTrue(Bundle(for: $0).dd.isUIKit) }
        someNonUIKitClasses.forEach { XCTAssertFalse(Bundle(for: $0).dd.isUIKit) }
    }
}
