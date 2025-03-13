/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM
@testable import DatadogInternal
import SwiftUI

class SwiftUIViewNameExtractorTests: XCTestCase {
    var extractor: SwiftUIReflectionBasedViewNameExtractor! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        extractor = SwiftUIReflectionBasedViewNameExtractor()
    }

    override func tearDown() {
        extractor = nil
        super.tearDown()
    }

    // MARK: - View Name Extraction Tests
    func testViewNameExtraction() {
        let testCases: [(String, String)] = [
            ("LazyView<ContentView>", "ContentView"),
            ("SheetContent<Text>", "Text"),
            ("Optional<Text>", "Text"),
            ("Optional<ProfileView>", "ProfileView"),
            ("LazyView<HomeView>", "HomeView"),
            ("ParameterizedLazyView<String, DetailViewForNavigationDestination>", "DetailViewForNavigationDestination"),
            ("DetailView.Type", "DetailView"),
            ("SheetContent<ModalSheet>", "ModalSheet")
        ]

        for (input, expected) in testCases {
            let result = extractor.extractViewName(from: input)
            XCTAssertEqual(result, expected, "Failed to extract from: \(input)")
        }
    }

    // MARK: - SwiftUIViewPath Tests
    func testSwiftUIViewPathComponents() {
        XCTAssertEqual(
            SwiftUIViewPath.hostingController.pathComponents,
            ["host", "_rootView", "content", "storage", "view"]
        )
        XCTAssertEqual(
            SwiftUIViewPath.navigationStack.pathComponents,
            ["host", "_rootView", "storage", "view", "content", "content", "content"]
        )
        XCTAssertEqual(
            SwiftUIViewPath.navigationStackDetail.pathComponents,
            ["host", "_rootView", "storage", "view", "content", "content", "content", "content", "list", "item", "type"]
        )
        XCTAssertEqual(
            SwiftUIViewPath.navigationStackContainer.pathComponents,
            ["host", "_rootView", "storage", "view", "content", "content", "content", "root"]
        )
        XCTAssertEqual(
            SwiftUIViewPath.sheetContent.pathComponents,
            ["host", "_rootView", "storage", "view", "content"]
        )
    }

    // MARK: - Controller Detection Tests
    func testDetectControllerType() {
        // Define test cases with class name and expected controller type
        let testCases: [(String, ControllerType)] = [
            // Format: (className, expectedType)
            ("_TtGC7SwiftUI19UIHostingController", .hostingController),
            ("_TtGC7SwiftUI19UIHostingControllerVVS_7TabItem8RootView_", .tabItem),
            ("SwiftUI.UIKitNavigationController", .navigationController),
            ("NavigationStackHostingController", .navigationController),
            ("_TtGC7SwiftUI29PresentationHostingController", .modal),
            ("UIViewController", .unknown)
        ]

        for (className, expectedType) in testCases {
            XCTAssertEqual(ControllerType(className: className), expectedType, "Controller type detection failed for: \(className)")
        }
    }

    func testShouldSkipViewController() {
        let tabbarResult = extractor.shouldSkipViewController(viewController: UITabBarController())
        XCTAssertTrue(tabbarResult, "Skip logic failed for UITabBarController")
        let navigationControllerResult = extractor.shouldSkipViewController(viewController: UINavigationController())
        XCTAssertTrue(navigationControllerResult, "Skip logic failed for UINavigationController")
        let viewControllerResult = extractor.shouldSkipViewController(viewController: UIViewController())
        XCTAssertFalse(viewControllerResult, "Skip logic failed for UIViewController")
    }
}
