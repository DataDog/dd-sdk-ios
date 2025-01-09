/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import SwiftUI
@testable import DatadogSessionReplay

class FrameworkUtilsTests: XCTestCase {
    // MARK: - isSwiftUI tests
    @available(iOS 13.0, *)
    func testIsSwiftUI_withNativeSwiftUIClasses() {
        // Given
        let nativeSwiftUIClass = UIHostingController<AnyView>.self

        // Then
        XCTAssertTrue(FrameworkUtils.isSwiftUI(class: nativeSwiftUIClass))
    }

    @available(iOS 13.0, *)
    func testIsSwiftUI_withCustomSwiftUIHostingController() {
        // Given
        class CustomHostingController: UIHostingController<AnyView> {}
        let customSwiftUIClass = CustomHostingController.self

        // Then
        XCTAssertTrue(FrameworkUtils.isSwiftUI(class: customSwiftUIClass))
    }

    @available(iOS 13.0, *)
    func testIsSwiftUI_withNonSwiftUIClasses() {
        // Given
        let nonSwiftUIClasses: [AnyClass] = [
            UIViewController.self,
            UIButton.self,
            NSObject.self
        ]

        // Then
        nonSwiftUIClasses.forEach {
            XCTAssertFalse(FrameworkUtils.isSwiftUI(class: $0))
        }
    }

    // MARK: - isUIKit tests
    func testIsUIKit_withNativeUIKitClasses() {
        // Given
        let nativeUIKitClasses: [AnyClass] = [
            UIViewController.self,
            UIButton.self,
            UINavigationBar.self
        ]

        // Then
        nativeUIKitClasses.forEach {
            XCTAssertTrue(FrameworkUtils.isUIKit(class: $0))
        }
    }

    func testIsUIKit_withCustomUIViewControllerSubclass() {
        // Given
        class CustomViewController: UIViewController {}
        let customUIKitClass = CustomViewController.self

        // Then
        XCTAssertTrue(FrameworkUtils.isUIKit(class: customUIKitClass))
    }

    func testIsUIKit_withNonUIKitClasses() {
        // Given
        let nonUIKitClasses: [AnyClass] = [
            NSObject.self,
            OperationQueue.self
        ]

        // Then
        nonUIKitClasses.forEach {
            XCTAssertFalse(FrameworkUtils.isUIKit(class: $0))
        }
    }
}
