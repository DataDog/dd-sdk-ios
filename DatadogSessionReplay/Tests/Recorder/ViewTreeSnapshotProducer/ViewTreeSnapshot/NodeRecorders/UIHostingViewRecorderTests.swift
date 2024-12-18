/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import SwiftUI
import DatadogInternal
import TestUtilities

@_spi(Internal)
@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
class UIHostingViewRecorderTests: XCTestCase {
    func testTextView() throws {
        struct MockView: View {
            var body: some View {
                Text("Hello, World!")
                    .font(.system(size: 28))
            }
        }

        let wireframes = try render(MockView())
        XCTAssertEqual(wireframes.count, 1)
        let wireframe = try XCTUnwrap(wireframes.first?.textWireframe)
        XCTAssertEqual(wireframe.text, "Hello, World!")
        XCTAssertEqual(wireframe.textStyle.color, "#000000FF")
        XCTAssertEqual(wireframe.textStyle.family, "-apple-system, BlinkMacSystemFont, \'Roboto\', sans-serif")
        XCTAssertEqual(wireframe.textStyle.size, 28)
        XCTAssertEqual(wireframe.x, 74, accuracy: 5)
        XCTAssertEqual(wireframe.y, 164, accuracy: 5)
        XCTAssertEqual(wireframe.width, 151, accuracy: 5)
        XCTAssertEqual(wireframe.height, 34, accuracy: 5)
    }

    @available(iOS 17.0, tvOS 17.0, *)
    func testScrollView() throws {
        struct MockView: View {
            var body: some View {
                ScrollView {
                    VStack {
                        Text("Hello, World!")
                            .font(.system(size: 17))
                    }
                    .frame(width: 300, height: 600)
                }
                .contentMargins(50)
            }
        }

        let wireframes = try render(MockView())
        XCTAssertEqual(wireframes.count, 1)
        let wireframe = try XCTUnwrap(wireframes.first?.textWireframe)
        XCTAssertEqual(wireframe.text, "Hello, World!")
        XCTAssertEqual(wireframe.x, 101, accuracy: 5)
        XCTAssertEqual(wireframe.y, 402, accuracy: 5)
        XCTAssertEqual(wireframe.width, 97, accuracy: 5)
        XCTAssertEqual(wireframe.height, 20, accuracy: 5)
    }
}

/// Renders a `SwiftUI.View` and builds a wireframe representation.
///
/// - Parameters:
///   - view: The `SwiftUI.View` instance.
///   - size: The container size.
///   - attributes: Optional host view attributes.
///   - context: Optional host view context.
/// - Returns: The SessionReplay wireframes representing the view.
@available(iOS 13.0, tvOS 13.0, *)
private func render<V>(
    _ view: V,
    size: CGSize = CGSize(width: 300, height: 300),
    with attributes: ViewAttributes = .mockAny(),
    in context: ViewTreeRecordingContext = .mockAny()
) throws -> [SRWireframe] where V: SwiftUI.View {
    let recorder: UIHostingViewRecorder
    if #available(iOS 18.1, tvOS 18.1, *) {
        recorder = iOS18HostingViewRecorder(identifier: UUID())
    } else {
        recorder = UIHostingViewRecorder(identifier: UUID())
    }

    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    let host = UIHostingController(rootView: view)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.resignKey() }
    window.layoutIfNeeded()

    let semantics = recorder.semantics(of: host.view, with: attributes, in: context)
    let builder = try XCTUnwrap(semantics?.nodes.first?.wireframesBuilder as? SwiftUIWireframesBuilder)
    var wireframes = builder.buildWireframes(with: WireframesBuilder())
    // remove first wireframe that represent the root hosting view
    wireframes.removeFirst()
    return wireframes
}

#endif
