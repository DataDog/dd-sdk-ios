/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import SwiftUI
@testable import DatadogRUM
@testable import DatadogInternal

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
        let testCases: [(String, String?)] = [
            // Format: (input, expectedExtractedName)
            ("LazyView<ViewType>", "ViewType"),
            ("SheetContent<Text>", "Text"),
            ("Optional<Text>", "Text"),
            ("Optional<ViewType>", "ViewType"),
            ("ParameterizedLazyView<String, ViewType>", "ViewType"),
            ("ParameterizedLazyView<String, ViewType>(value: \"xxx\", content: (Function))", "ViewType"),
            ("ViewType.Type", "ViewType"),
            ("SheetContent<ViewType>", "ViewType"),
            ("ModifiedView<ModifierType, ModifiedView<ModifierType, ModifiedView<ModifierType, ModifiedView<ModifierType, ViewType>>>>", "ViewType"),
            ("ModifiedView<ModifierType, ModifiedView<ModifierType, ModifiedView<ModifierType, ModifiedView<ModifierType, ContainerType<ViewType>>>>>", "ViewType"),
            ("DetailView", "DetailView")
        ]

        for (input, expected) in testCases {
            let result = extractor.extractViewName(from: input)
            XCTAssertEqual(result, expected, "Failed to extract from: \(input)")
        }
    }

    func testFallbackViewNameExtraction() {
        let testCases: [(String, String)] = [
            // Format: (input, expectedExtractedName)
            // Hosting Controller cases
            ("UIHostingController<HomeView>", "HomeView"),
            ("UIHostingController<AnyView>", "UIHostingController<AnyView>"),
            ("UIHostingController<ModifiedContent<ModifiedContent<Element, NavigationColumnModifier>, StyleContextWriter<SidebarStyleContext>>>", "AutoTracked_HostingController_Fallback"),
            // Navigation Stack Hosting Controller cases
            ("NavigationStackHostingController<DetailView>", "DetailView"),
            ("NavigationStackHostingController<AnyView>", "NavigationStackHostingController<AnyView>"),
            ("NavigationStackHostingController<ModifiedContent<ModifiedContent<Element, NavigationColumnModifier>, StyleContextWriter<SidebarStyleContext>>>", "AutoTracked_NavigationStackController_Fallback")
        ]

        for (input, expected) in testCases {
            // Use the internal method directly
            let result = extractor.extractFallbackViewName(from: input)
            XCTAssertEqual(result, expected, "Failed to extract fallback name from: \(input)")
        }
    }

    // MARK: - SwiftUIViewPath Tests
    func testSwiftUIViewPathComponents() {
        // HostingController cases
        XCTAssertEqual(
            SwiftUIViewPath.hostingControllerModifiedContent.pathComponents,
            [.host, .rootView, .content, .storage, .view]
        )
        XCTAssertEqual(
            SwiftUIViewPath.hostingControllerRootView.pathComponents,
            [.host, .rootView, .content, .storage, .view, .content, .storage, .view, .content, .content]
        )
        XCTAssertEqual(
            SwiftUIViewPath.hostingControllerBase.pathComponents,
            [.host, .rootView]
        )
        // NavigationStack cases
        XCTAssertEqual(
            SwiftUIViewPath.navigationStackBase.pathComponents,
            [.host, .rootView, .storage, .view, .content, .content, .content]
        )
        XCTAssertEqual(
            SwiftUIViewPath.navigationStackContent.pathComponents,
            [.host, .rootView, .storage, .view, .content, .content, .content, .content, .list, .item, .type]
        )
        XCTAssertEqual(
            SwiftUIViewPath.navigationStackAnyView.pathComponents,
            [.host, .rootView, .storage, .view, .content, .content, .content, .root]
        )
        // Modal case
        XCTAssertEqual(
            SwiftUIViewPath.sheetContent.pathComponents,
            [.host, .rootView, .storage, .view, .content]
        )
    }

    // MARK: - Controller Detection Tests
    @available(iOS 13.0, tvOS 13.0, *)
    func testDetectControllerType() {
        // Define test cases with controller, class name and expected controller type
        let testCases: [(String, ControllerType)] = [
            // Format: (controller, className, expectedType)
            ("_TtGC7SwiftUI19UIHostingController", .hostingController),
            ("SwiftUI.UIKitNavigationController", .navigationStackHostingController),
            ("NavigationStackHostingController", .navigationStackHostingController),
            ("_TtGC7SwiftUI29PresentationHostingController", .modal),
            ("UIViewController", .unknown)
        ]

        for (className, expectedType) in testCases {
            XCTAssertEqual(ControllerType(from: className), expectedType, "Controller type detection failed for: \(className)")
        }
    }

    func testShouldSkipViewController() {
        let navigationController = UINavigationController()
        let mockViewController = UIViewController()

        // Test cases with controller and class name
        let testCases: [(UIViewController, String, Bool)] = [
            // Format: (controller, className, expectedShouldSkipResult)
            // TabBarController cases
            (mockViewController, "SwiftUI.UIKitTabBarController", true),
            (mockViewController, "SwiftUI.TabHostingController", true),
            (mockViewController, "_TtGC7SwiftUI19UIHostingControllerVVS_7TabItem8RootView_", true),
            // NavigationController case
            (navigationController, navigationController.canonicalClassName, true),
            // Other ViewControllers cases
            (mockViewController, "SwiftUI.NotifyingMulticolumnSplitViewController", true),
            (mockViewController, mockViewController.canonicalClassName, false),
        ]

        for (controller, className, expectedResult) in testCases {
            let result = extractor.shouldSkipViewController(viewController: controller, className: className)
            XCTAssertEqual(result, expectedResult, "Skip logic failed for \(className)")
        }
    }

    func testExtractNameFilteringForUIKitControllers() {
        let tabbar = UITabBarController()
        let pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        let splitViewController = UISplitViewController()

        // Should return nil for UIKit bundle controllers
        XCTAssertNil(extractor.extractName(from: tabbar))
        XCTAssertNil(extractor.extractName(from: pageViewController))
        XCTAssertNil(extractor.extractName(from: splitViewController))

        if #available(iOS 13.0, tvOS 13.0, *) {
            let hostingController = UIHostingController(rootView: EmptyView())
            XCTAssertNotNil(hostingController)
        }
    }
}
