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
    private enum Constants {
        static let bundledImageName = "dd_logo"
        static let nonBundledImageName = "flower"
    }

    // MARK: Text
    func testTextView() throws {
        let wireframes = try render(MockTextView())
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

    func testTextView_withMaskAllPrivacy() throws {
        let wireframes = try render(
            MockTextView(),
            in: ViewTreeRecordingContext.mockWith(
                recorder: .mockWith(
                    textAndInputPrivacy: .maskAll
                )
            )
        )

        XCTAssertEqual(wireframes.count, 1)
        let wireframe = try XCTUnwrap(wireframes.first?.textWireframe)
        XCTAssertEqual(wireframe.text, "xxxxxx xxxxxx")
        XCTAssertEqual(wireframe.textStyle.color, "#000000FF")
        XCTAssertEqual(wireframe.textStyle.family, "-apple-system, BlinkMacSystemFont, \'Roboto\', sans-serif")
        XCTAssertEqual(wireframe.textStyle.size, 28)
        XCTAssertEqual(wireframe.x, 74, accuracy: 5)
        XCTAssertEqual(wireframe.y, 164, accuracy: 5)
        XCTAssertEqual(wireframe.width, 151, accuracy: 5)
        XCTAssertEqual(wireframe.height, 34, accuracy: 5)
    }

    // MARK: Scroll View
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

    // MARK: Shape
    func testShapeView() throws {
        struct MockView: View {
            var body: some View {
                Circle()
                    .fill(Color.red)
                    .frame(width: 100, height: 100)
            }
        }

        let wireframes = try render(MockView())
        XCTAssertEqual(wireframes.count, 1)
        let wireframe = try XCTUnwrap(wireframes.first?.shapeWireframe)
        XCTAssertEqual(wireframe.x, 100, accuracy: 5)
        XCTAssertEqual(wireframe.y, 130, accuracy: 5)
        XCTAssertEqual(wireframe.width, 100, accuracy: 5)
        XCTAssertEqual(wireframe.height, 100, accuracy: 5)
        XCTAssertEqual(wireframe.shapeStyle?.backgroundColor, "#1022A00FF")
    }

    // MARK: Image
    func testImageView() throws {
        let testCases: [
            (imageName: String, privacy: ImagePrivacyLevel, expectedPlaceholder: Bool)
        ] = [
            (Constants.bundledImageName, .maskNone, false),
            (Constants.bundledImageName, .maskNonBundledOnly, false),
            (Constants.bundledImageName, .maskAll, true),
            (Constants.nonBundledImageName, .maskNone, false),
            (Constants.nonBundledImageName, .maskNonBundledOnly, true),
            (Constants.nonBundledImageName, .maskAll, true)
        ]

        for (imageName, privacy, expectsPlaceholder) in testCases {
            let wireframes = try render(
                MockImageView(imageName: imageName),
                in: ViewTreeRecordingContext.mockWith(
                    recorder: .mockWith(imagePrivacy: privacy)
                )
            )

            XCTAssertEqual(wireframes.count, 1, "Expected one wireframe for \(imageName) with privacy: \(privacy)")

            if expectsPlaceholder {
                let placeholder = try XCTUnwrap(wireframes.first?.placeholderWireframe, "Expected a placeholder wireframe")
                XCTAssertEqual(placeholder.x, 100, accuracy: 5)
                XCTAssertEqual(placeholder.y, 122, accuracy: 5)
                XCTAssertEqual(placeholder.width, 100, accuracy: 5)
                XCTAssertEqual(placeholder.height, 116, accuracy: 5)
            } else {
                let imageWireframe = try XCTUnwrap(wireframes.first?.imageWireframe, "Expected an image wireframe")
                XCTAssertEqual(imageWireframe.x, 100, accuracy: 5)
                XCTAssertEqual(imageWireframe.y, 122, accuracy: 5)
                XCTAssertEqual(imageWireframe.width, 100, accuracy: 5)
                XCTAssertEqual(imageWireframe.height, 116, accuracy: 5)
            }
        }
    }

    func testImage_withUnsupportedType_itDoesNotRecordImage() throws {
        struct MockView: View {
            var body: some View {
                Image(systemName: "star.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
            }
        }

        let wireframes = try render(
            MockView(),
            in: ViewTreeRecordingContext.mockWith(
                recorder: .mockWith(
                    imagePrivacy: .maskNone
                )
            )
        )

        XCTAssertEqual(wireframes.count, 1)
        let wireframe = try XCTUnwrap(wireframes.first?.shapeWireframe)
        XCTAssertEqual(wireframe.x, 125, accuracy: 5)
        XCTAssertEqual(wireframe.y, 155, accuracy: 5)
        XCTAssertEqual(wireframe.width, 50, accuracy: 5)
        XCTAssertEqual(wireframe.height, 50, accuracy: 5)
    }

    // MARK: Other cases
    func testNestedViews() throws {
        struct MockNestedView: View {
            var body: some View {
                VStack {
                    Text("Top")
                    HStack {
                        Text("Left")
                        Text("Right")
                    }
                }
            }
        }

        let wireframes = try render(MockNestedView())
        XCTAssertEqual(wireframes.count, 3)
        let firstWireframe = try XCTUnwrap(wireframes.first?.textWireframe)
        XCTAssertEqual(firstWireframe.x, 136, accuracy: 5)
        XCTAssertEqual(firstWireframe.y, 158, accuracy: 5)
        XCTAssertEqual(firstWireframe.width, 28, accuracy: 5)
        XCTAssertEqual(firstWireframe.height, 20, accuracy: 5)
        let secondWireframe = try XCTUnwrap(wireframes[1].textWireframe)
        XCTAssertEqual(secondWireframe.x, 111, accuracy: 5)
        XCTAssertEqual(secondWireframe.y, 181, accuracy: 5)
        XCTAssertEqual(secondWireframe.width, 30, accuracy: 5)
        XCTAssertEqual(secondWireframe.height, 20, accuracy: 5)
        let thirdWireframe = try XCTUnwrap(wireframes[2].textWireframe)
        XCTAssertEqual(thirdWireframe.x, 149, accuracy: 5)
        XCTAssertEqual(thirdWireframe.y, 181, accuracy: 5)
        XCTAssertEqual(thirdWireframe.width, 40, accuracy: 5)
        XCTAssertEqual(thirdWireframe.height, 20, accuracy: 5)
    }

    func testEmptyTextView_itShouldNotRecord() throws {
        struct MockView: View {
            var body: some View {
                Text("")
            }
        }

        let wireframes = try render(MockView())
        XCTAssertEqual(wireframes.count, 0)
    }

    func testInvisibleView_itShouldNotRecord() throws {
        struct MockView: View {
            var body: some View {
                Text("Hidden").frame(width: 0, height: 0)
            }
        }

        let wireframes = try render(MockView())
        XCTAssertEqual(wireframes.count, 0)
    }

    func testUIKitView_itShouldNotRecord() throws {
        struct UIKitView: UIViewRepresentable {
            func makeUIView(context: Context) -> UIView {
                let view = UIView()
                view.backgroundColor = .red
                return view
            }
            func updateUIView(_ uiView: UIView, context: Context) {}
        }

        struct MockView: View {
            var body: some View {
                UIKitView().frame(width: 100, height: 100)
            }
        }

        // When
        let wireframes = try render(MockView())

        // Then
        XCTAssertEqual(wireframes.count, 0)
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

@available(iOS 13.0, *)
private struct MockImageView: View {
    static let bundle = Bundle(for: UIHostingViewRecorderTests.self)
    let imageName: String

    var body: some View {
        Image(imageName, bundle: MockImageView.bundle)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 100, height: 100)
            .clipped()
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private struct MockTextView: View {
    var body: some View {
        Text("Hello, World!")
            .font(.system(size: 28))
    }
}
#endif
