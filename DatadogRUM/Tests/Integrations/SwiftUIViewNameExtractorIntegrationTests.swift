/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import SwiftUI
@testable import DatadogRUM
@testable import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
class SwiftUIViewNameExtractorIntegrationTests: XCTestCase {
    // MARK: SwiftUIViewPath Tests
    func testSwiftUIViewPath_hostingController() {
        let mockReflector = MockReflector()
        mockReflector.descendantHandler = { paths in
            // Verify paths match what we expect
            if paths.count == 5,
               case .key("host") = paths[0],
               case .key("_rootView") = paths[1],
               case .key("content") = paths[2],
               case .key("storage") = paths[3],
               case .key("view") = paths[4] {
                return "dummy-value"
            }
            return nil
        }

        // Test the path traversal
        let result = SwiftUIViewPath.hostingController.traverse(with: mockReflector)
        XCTAssertNotNil(result)
        XCTAssertEqual(mockReflector.lastCalledPaths.count, 5)
        verifyPathContainsKeys(
            mockReflector.lastCalledPaths,
            keys: ["host", "_rootView", "content", "storage", "view"]
        )
    }

    func testSwiftUIViewPath_navigationStack() {
        let mockReflector = MockReflector()
        mockReflector.descendantHandler = { paths in
            // Verify paths match what we expect
            if paths.count == 7,
               case .key("host") = paths[0],
               case .key("_rootView") = paths[1],
               case .key("storage") = paths[2],
               case .key("view") = paths[3],
               case .key("content") = paths[4],
               case .key("content") = paths[5],
               case .key("content") = paths[6] {
                return "dummy-value"
            }
            return nil
        }

        // Test the path traversal
        let result = SwiftUIViewPath.navigationStack.traverse(with: mockReflector)
        XCTAssertNotNil(result)
        XCTAssertEqual(mockReflector.lastCalledPaths.count, 7)
        verifyPathContainsKeys(
            mockReflector.lastCalledPaths,
            keys: ["host", "_rootView", "storage", "view", "content", "content", "content"]
        )
    }

    func testSwiftUIViewPath_navigationStackContainer() {
        let mockReflector = MockReflector()
        mockReflector.descendantHandler = { paths in
            // Verify paths match what we expect
            if paths.count == 8,
               case .key("host") = paths[0],
               case .key("_rootView") = paths[1],
               case .key("storage") = paths[2],
               case .key("view") = paths[3],
               case .key("content") = paths[4],
               case .key("content") = paths[5],
               case .key("content") = paths[6],
               case .key("root") = paths[7] {
                return "dummy-value"
            }
            return nil
        }

        // Test the path traversal
        let result = SwiftUIViewPath.navigationStackContainer.traverse(with: mockReflector)
        XCTAssertNotNil(result)
        XCTAssertEqual(mockReflector.lastCalledPaths.count, 8)
        verifyPathContainsKeys(
            mockReflector.lastCalledPaths,
            keys: ["host", "_rootView", "storage", "view", "content", "content", "content", "root"]
        )
    }

    func testSwiftUIViewPath_navigationStackDetail() {
        let mockReflector = MockReflector()
        mockReflector.descendantHandler = { paths in
            if paths.count == 11,
               case .key("host") = paths[0],
               case .key("_rootView") = paths[1],
               case .key("storage") = paths[2],
               case .key("view") = paths[3],
               case .key("content") = paths[4],
               case .key("content") = paths[5],
               case .key("content") = paths[6],
               case .key("content") = paths[7],
               case .key("list") = paths[8],
               case .key("item") = paths[9],
               case .key("type") = paths[10] {
                return "dummy-value"
            }
            return nil
        }

        // Test the path traversal
        let result = SwiftUIViewPath.navigationStackDetail.traverse(with: mockReflector)
        XCTAssertNotNil(result)
        XCTAssertEqual(mockReflector.lastCalledPaths.count, 11)
        verifyPathContainsKeys(
            mockReflector.lastCalledPaths,
            keys: ["host", "_rootView", "storage", "view", "content", "content", "content", "content", "list", "item", "type"]
        )
    }

    func testSwiftUIViewPath_sheetContent() {
        let mockReflector = MockReflector()
        mockReflector.descendantHandler = { paths in
            if paths.count == 5,
               case .key("host") = paths[0],
               case .key("_rootView") = paths[1],
               case .key("storage") = paths[2],
               case .key("view") = paths[3],
               case .key("content") = paths[4] {
                return "dummy-value"
            }
            return nil
        }

        // Test the path traversal
        let result = SwiftUIViewPath.sheetContent.traverse(with: mockReflector)
        XCTAssertNotNil(result)
        XCTAssertEqual(mockReflector.lastCalledPaths.count, 5)
        verifyPathContainsKeys(
            mockReflector.lastCalledPaths,
            keys: ["host", "_rootView", "storage", "view", "content"]
        )
    }

    // MARK: - Helper method
    private func verifyPathContainsKeys(_ paths: [ReflectionMirror.Path], keys: [String]) {
        XCTAssertEqual(paths.count, keys.count)
        for key in keys {
            XCTAssertTrue(
                paths.contains { path in
                    if case .key(let pathKey) = path, pathKey == key {
                        return true
                    }
                    return false
                },
                "Path key '\(key)' was not requested"
            )
        }
    }
}

// MARK: - MockReflector
/// Mock implementation of the `TopLevelReflector` protocol for testing path traversal.
private class MockReflector: TopLevelReflector {
    /// Handler that determines what to return for requested paths.
    ///
    /// The handler receives the full list of requested path components and returns
    /// either a value (to simulate finding something at that path) or nil (to simulate
    /// a path that doesn't exist).
    var descendantHandler: (([ReflectionMirror.Path]) -> Any?)?

    /// Records the most recently requested paths for verification.
    var lastCalledPaths: [ReflectionMirror.Path] = []

    /// Implements the `TopLevelReflector` protocol method by recording the requested path
    /// and delegating to the handler to determine the return value.
    func descendant(_ paths: [ReflectionMirror.Path]) -> Any? {
        lastCalledPaths = paths
        if let handler = descendantHandler {
            return handler(lastCalledPaths)
        }

        return nil
    }
}
