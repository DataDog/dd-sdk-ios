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

    // MARK: - Hosting Controller Tests
    func testHostingController() {
        // Given
        let testCases = [
            ("SwiftUI.LazyView<MyApp.HomeView>(content: (Function))", "HomeView"),
            ("SwiftUI.LazyView<SwiftUI.ModifiedContent<MyApp.RootView, SwiftUI._AppearanceActionModifier>>(content: (Function))", "RootView")
        ]

        // When/Then
        for (input, expected) in testCases {
            let result = extractor.extractViewNameFromHostingViewController(input)
            XCTAssertEqual(result, expected, "Failed to extract from: \(input)")
        }
    }

    // MARK: - Tests: Navigation Stack View Name Extraction
    func testNavigationStack() {
        // Given
        let testCases = [
            ("MyApp.DetailView.self", "DetailView"),
            ("MyApp.DetailView()", "DetailView"),
            ("SwiftUI.ParameterizedLazyView<Swift.String, MyApp.DetailView>", "DetailView"),
            ("SwiftUI.ParameterizedLazyView<Swift.String, MyApp.DetailView>(\n  value: Detail A,\n  content: (Function)\n)", "DetailView"),
            ("SwiftUI.Text(\n  storage: .anyTextStorage(\n    SwiftUI.(unknown context at $1d30c62cc).LocalizedTextStorage(\n      key: SwiftUI.LocalizedStringKey(\n        key: Detail View,\n        hasFormatting: false,\n        arguments: []\n      ),\n      table: nil,\n      bundle: nil\n    )\n  ),\n  modifiers: []\n)", "Text")
        ]

        // When/Then
        for (input, expected) in testCases {
            let result = extractor.extractViewNameFromNavigationStackHostingController(input)
            XCTAssertEqual(result, expected, "Failed to extract from type reference: \(input)")
        }
    }

    // MARK: - Tests: Sheet Content Name Extraction
    func testSheetContent() {
        // Given
        let testCases = [
            ("SwiftUI.(unknown context at $1d3108fec).SheetContent<MyApp.FullScreenView>(content: MyApp.FullScreenView(_dismiss: SwiftUI.Environment<SwiftUI.DismissAction>(content: .keyPath(Swift.KeyPath<SwiftUI.EnvironmentValues, SwiftUI.DismissAction>(_kvcKeyPathStringPtr: nil)))))", "FullScreenView")
        ]

        // When
        // When/Then
        for (input, expected) in testCases {
            let result = extractor.extractViewNameFromSheetContent(input)
            XCTAssertEqual(result, expected, "Failed to extract from: \(input)")
        }
    }

    // MARK: - Controller Detection Tests
    func testDetectControllerType() {
        // Define test cases with class name and expected controller type
        let testCases: [(String, SwiftUIReflectionBasedViewNameExtractor.ControllerType)] = [
            // Format: (className, expectedType)
            ("_TtGC7SwiftUI19UIHostingController", .hostingController),
            ("_TtGC7SwiftUI19UIHostingControllerVVS_7TabItem8RootView_", .tabItem),
            ("SwiftUI.UIKitNavigationController", .navigationController),
            ("NavigationStackHostingController", .navigationController),
            ("_TtGC7SwiftUI29PresentationHostingController", .modal),
            ("UIViewController", .unknown)
        ]

        for (className, expectedType) in testCases {
            let result = extractor.detectControllerType(className: className)
            XCTAssertEqual(result, expectedType, "Controller type detection failed for: \(className)")
        }
    }

    func testShouldSkipViewController() {
        let testCases = [
            // Format: (className, isUINavigationController, shouldSkip)
            ("SwiftUI.UIKitTabBarController", false, true),
            ("UINavigationController", true, true),
            ("_TtGC7SwiftUI19UIHostingController", false, false),
            ("_TtGC7SwiftUI19UIHostingControllerVVS_7TabItem8RootView_", false, false),
            ("_TtGC7SwiftUI29PresentationHostingController", false, false),
            ("NavigationStackHostingController", false, false)
        ]

        for (className, isNavController, expectedResult) in testCases {
            let mockVC = isNavController ? UINavigationController() : UIViewController()
            let result = extractor.shouldSkipViewController(className: className, viewController: mockVC)
            XCTAssertEqual(result, expectedResult, "Skip logic failed for: \(className)")
        }
    }

    // MARK: - Performance Tests
    /// Tests the performance of string parsing for view name extraction
    @available(iOS 13.0, tvOS 13.0, *)
    func testStringParsingPerformance() {
        // Inputs to test different parsing functions
        let hostingInput = "SwiftUI.LazyView<MyApp.HomeView>(content: (Function))"
        let navigationInput = "MyApp.DetailView()"
        let sheetInput = "SwiftUI.(unknown context at $1d3108fec).SheetContent<MyApp.SettingsView>(content: MyApp.SettingsView())"

        // Performance threshold
        #if os(tvOS)
        let performanceThresholdInSeconds = 0.001 // 1 ms for tvOS
        #else
        let performanceThresholdInSeconds = 0.0005 // 0.5 ms for iOS
        #endif
        let iterations = 100
        let startTime = CACurrentMediaTime()

        for _ in 0..<iterations {
            _ = extractor.extractViewNameFromHostingViewController(hostingInput)
            _ = extractor.extractViewNameFromNavigationStackHostingController(navigationInput)
            _ = extractor.extractViewNameFromSheetContent(sheetInput)
        }

        let endTime = CACurrentMediaTime()
        let totalTime = endTime - startTime
        let averageTime = totalTime / Double(iterations)

        // Assert performance is acceptable
        XCTAssertLessThan(
            averageTime,
            performanceThresholdInSeconds,
            "Performance regression detected: \(averageTime * 1_000) ms exceeds threshold of \(performanceThresholdInSeconds * 1_000) ms"
        )
    }
}
