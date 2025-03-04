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
    // MARK: Tests
    func testHostingController_itExtractsTheViewName() throws {
        // Fixture dump
        let dumpFixture = """
        SwiftUI.UIHostingController<SwiftUI.ModifiedContent<SwiftUI.AnyView, SwiftUI.RootModifier>>(
          allowedBehaviors: SwiftUI.HostingControllerAllowedBehaviors(rawValue: 0),
          requiredBridges: SwiftUI.HostingControllerBridges(rawValue: 179),
          host: SwiftUI._UIHostingView<SwiftUI.ModifiedContent<SwiftUI.AnyView, SwiftUI.RootModifier>>(
            _rootView: SwiftUI.ModifiedContent<SwiftUI.AnyView, SwiftUI.RootModifier>(
              content: SwiftUI.AnyView(
                storage: SwiftUI.(unknown context at $1d30dd964).AnyViewStorage<SwiftUI.LazyView<SwiftUITest.HomeView>>(
                  view: SwiftUI.LazyView<SwiftUITest.HomeView>(content: (Function))
                )
              ),
            ),
          )
        )
        """

        let (extractor, mockReflector) = createTestComponents(
            mockOutput: dumpFixture,
            reflectorHandler: { paths in
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
        )

        let extractedName = extractor.extractHostingControllerPath(with: mockReflector)
        XCTAssertNotNil(extractedName)
        let requiredKeys = ["host", "_rootView", "content", "storage", "view"]
        verifyPathContainsKeys(mockReflector.lastCalledPaths, keys: requiredKeys)
    }

    func testNavigationStackContainer_itIsIgnored() throws {
        // Fixture dump
        let dumpFixture = """
        SwiftUI.NavigationStackHostingController<SwiftUI.AnyView>(
          allowedBehaviors: SwiftUI.HostingControllerAllowedBehaviors(rawValue: 0),
          requiredBridges: SwiftUI.HostingControllerBridges(rawValue: 17),
          host: SwiftUI.NavigationStackHostingController<SwiftUI.AnyView>.(unknown context at $1d26184a0).HostingView(
            _rootView: SwiftUI.AnyView(
              storage: SwiftUI.(unknown context at $1d30dd964).AnyViewStorage<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI._VariadicView.Tree<SwiftUI._VStackLayout, SwiftUI._VariadicView_Children>, SwiftUI.(unknown context at $1d26188a0).ReadDestinationsModifier<SwiftUI.ResolvedNavigationDestinations>>, SwiftUI._PreferenceTransformModifier<SwiftUI.NavigationDestinationKey>>, SwiftUI.ModifiedContent<SwiftUI.NavigationColumnModifier, SwiftUI.ModifiedContent<SwiftUI.InjectKeyModifier, SwiftUI.(unknown context at $1d26044a4).NavigationBackgroundReaderModifier>>>>(
                view: SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI._VariadicView.Tree<SwiftUI._VStackLayout, SwiftUI._VariadicView_Children>, SwiftUI.(unknown context at $1d26188a0).ReadDestinationsModifier<SwiftUI.ResolvedNavigationDestinations>>, SwiftUI._PreferenceTransformModifier<SwiftUI.NavigationDestinationKey>>, SwiftUI.ModifiedContent<SwiftUI.NavigationColumnModifier, SwiftUI.ModifiedContent<SwiftUI.InjectKeyModifier, SwiftUI.(unknown context at $1d26044a4).NavigationBackgroundReaderModifier>>>(
                  content: SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI._VariadicView.Tree<SwiftUI._VStackLayout, SwiftUI._VariadicView_Children>, SwiftUI.(unknown context at $1d26188a0).ReadDestinationsModifier<SwiftUI.ResolvedNavigationDestinations>>, SwiftUI._PreferenceTransformModifier<SwiftUI.NavigationDestinationKey>>(
                    content: SwiftUI.ModifiedContent<SwiftUI._VariadicView.Tree<SwiftUI._VStackLayout, SwiftUI._VariadicView_Children>, SwiftUI.(unknown context at $1d26188a0).ReadDestinationsModifier<SwiftUI.ResolvedNavigationDestinations>>(
                      content: SwiftUI._VariadicView.Tree<SwiftUI._VStackLayout, SwiftUI._VariadicView_Children>(
                        root: SwiftUI._VStackLayout(
                          alignment: SwiftUI.HorizontalAlignment(
                            key: SwiftUI.AlignmentKey(bits: 2)
                          ),
                          spacing: nil
                        ),
                    ),
                ),
            ),
        ),
        """

        let (extractor, mockReflector) = createTestComponents(
            mockOutput: dumpFixture,
            reflectorHandler: { paths in
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
        )

        let extractedName = extractor.extractNavigationControllerPath(reflector: mockReflector)
        XCTAssertNil(extractedName)
        let requiredKeys = ["host", "_rootView", "storage", "view", "content", "content", "content", "root"]
        verifyPathContainsKeys(mockReflector.lastCalledPaths, keys: requiredKeys)
    }

    func testNavigationStackHostingController_itExtractsTheViewName() throws {
        // Fixture dump
        let dumpFixture = """
        SwiftUI.NavigationStackHostingController<SwiftUI.AnyView>(
          allowedBehaviors: SwiftUI.HostingControllerAllowedBehaviors(rawValue: 0),
          requiredBridges: SwiftUI.HostingControllerBridges(rawValue: 17),
          host: SwiftUI.NavigationStackHostingController<SwiftUI.AnyView>.(unknown context at $1d26184a0).HostingView(
            _rootView: SwiftUI.AnyView(
              storage: SwiftUI.(unknown context at $1d30dd964).AnyViewStorage<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<Swift.Optional<SwiftUITest.ProfileView>, SwiftUI.(unknown context at $1d26188a0).ReadDestinationsModifier<SwiftUI.ResolvedNavigationDestinations>>, SwiftUI._PreferenceTransformModifier<SwiftUI.NavigationDestinationKey>>, SwiftUI.ModifiedContent<SwiftUI.NavigationColumnModifier, SwiftUI.ModifiedContent<SwiftUI.InjectKeyModifier, SwiftUI.(unknown context at $1d26044a4).NavigationBackgroundReaderModifier>>>>(
                view: SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<Swift.Optional<SwiftUITest.ProfileView>, SwiftUI.(unknown context at $1d26188a0).ReadDestinationsModifier<SwiftUI.ResolvedNavigationDestinations>>, SwiftUI._PreferenceTransformModifier<SwiftUI.NavigationDestinationKey>>, SwiftUI.ModifiedContent<SwiftUI.NavigationColumnModifier, SwiftUI.ModifiedContent<SwiftUI.InjectKeyModifier, SwiftUI.(unknown context at $1d26044a4).NavigationBackgroundReaderModifier>>>(
                  content: SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<Swift.Optional<SwiftUITest.ProfileView>, SwiftUI.(unknown context at $1d26188a0).ReadDestinationsModifier<SwiftUI.ResolvedNavigationDestinations>>, SwiftUI._PreferenceTransformModifier<SwiftUI.NavigationDestinationKey>>(
                    content: SwiftUI.ModifiedContent<Swift.Optional<SwiftUITest.ProfileView>, SwiftUI.(unknown context at $1d26188a0).ReadDestinationsModifier<SwiftUI.ResolvedNavigationDestinations>>(
                      content: SwiftUITest.ProfileView(),
                      )
                    ),
                ),
            ),
        ),
        """

        let (extractor, mockReflector) = createTestComponents(
            mockOutput: dumpFixture,
            reflectorHandler: { paths in
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
        )

        let extractedName = extractor.extractNavigationControllerPath(reflector: mockReflector)
        XCTAssertNotNil(extractedName)
        let requiredKeys = ["host", "_rootView", "storage", "view", "content", "content", "content"]
        verifyPathContainsKeys(mockReflector.lastCalledPaths, keys: requiredKeys)
    }

    func testSheetContent_itExtractsTheViewName() throws {
        // Fixture dump
        let dumpFixture = """
        SwiftUI.(unknown context at $1d25dfaac).SheetContent<SwiftUI.Text>(
            content: SwiftUI.Text(
                storage: .anyTextStorage(
                    SwiftUI.(unknown context at $1d30c62cc).LocalizedTextStorage(
                        key: SwiftUI.LocalizedStringKey(
                            key: Modal View,
                            hasFormatting: false,
                            arguments: []
                        ),
                        table: nil,
                        bundle: nil
                    )
                ),
              ),
            ),
          )
        )
        """

        let (extractor, mockReflector) = createTestComponents(
            mockOutput: dumpFixture,
            reflectorHandler: { paths in
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
        )

        let extractedName = extractor.extractSheetContentPath(with: mockReflector)
        XCTAssertNotNil(extractedName)
        let requiredKeys = ["host", "_rootView", "storage", "view", "content"]
        verifyPathContainsKeys(mockReflector.lastCalledPaths, keys: requiredKeys)
    }

    // MARK: TODO: RUM-8414 - Add more tests for each path extraction use case

    // MARK: - Helper method
    private func createTestComponents(
        mockOutput: String,
        reflectorHandler: @escaping ([ReflectionMirror.Path]) -> Any?
    ) -> (extractor: SwiftUIReflectionBasedViewNameExtractor, reflector: MockReflector) {
        let testDumper = TestDumper()
        testDumper.mockOutput = mockOutput

        let mockReflector = MockReflector()
        mockReflector.descendantIfPresentHandler = reflectorHandler

        let extractor = SwiftUIReflectionBasedViewNameExtractor(
            reflectorFactory: { _ in mockReflector },
            dumper: testDumper
        )

        return (extractor, mockReflector)
    }

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
/// Mock implementation of the `ReflectorType` protocol for testing path traversal.

private class MockReflector: ReflectorType {
    /// Handler that determines what to return for requested paths.
    ///
    /// The handler receives the full list of requested path components and returns
    /// either a value (to simulate finding something at that path) or nil (to simulate
    /// a path that doesn't exist).
    var descendantIfPresentHandler: (([ReflectionMirror.Path]) -> Any?)?

    /// Records the most recently requested paths for verification.
    var lastCalledPaths: [ReflectionMirror.Path] = []

    /// Implements the `ReflectorType` protocol method by recording the requested path
    /// and delegating to the handler to determine the return value.
    func descendantIfPresent(_ first: ReflectionMirror.Path, _ rest: ReflectionMirror.Path...) -> Any? {
        lastCalledPaths = [first] + rest

        if let handler = descendantIfPresentHandler {
            return handler(lastCalledPaths)
        }

        return nil
    }
}

// MARK: - TestDumper
/// Test dumper that returns predetermined output
/// `TestDumper` bypasses the actual dumping logic and instead returns a predetermined string.
private class TestDumper: Dumper {
    /// The predefined output string to return when `dump` is called.
    var mockOutput: String = ""

    /// Returns the predefined `mockOutput` instead of actually dumping the value.
    func dump<T, TargetStream>(_ value: T, to target: inout TargetStream) where TargetStream: TextOutputStream {
        target.write(mockOutput)
    }
}
