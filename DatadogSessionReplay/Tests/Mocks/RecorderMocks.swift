/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import XCTest
import UIKit
import WebKit

@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

// MARK: - ViewTreeSnapshot Mocks

extension ViewTreeSnapshot: AnyMockable, RandomMockable {
    public static func mockAny() -> ViewTreeSnapshot {
        return mockWith()
    }

    public static func mockRandom() -> ViewTreeSnapshot {
        return ViewTreeSnapshot(
            date: .mockRandom(),
            context: .mockRandom(),
            viewportSize: .mockRandom(),
            nodes: .mockRandom(count: .random(in: (5..<50))),
            webViewSlotIDs: .mockRandom()
        )
    }

    static func mockWith(
        date: Date = .mockAny(),
        context: Recorder.Context = .mockAny(),
        viewportSize: CGSize = .mockAny(),
        nodes: [Node] = .mockAny(),
        webViewSlotIDs: Set<Int> = .mockAny()
    ) -> ViewTreeSnapshot {
        return ViewTreeSnapshot(
            date: date,
            context: context,
            viewportSize: viewportSize,
            nodes: nodes,
            webViewSlotIDs: webViewSlotIDs
        )
    }
}

extension ViewAttributes: AnyMockable, RandomMockable {
    /// Placeholder mock, not guaranteeing consistency of returned `ViewAttributes`.
    public static func mockAny() -> ViewAttributes {
        return mockWith()
    }

    /// Random mock, not guaranteeing consistency of returned `ViewAttributes`.
    public static func mockRandom() -> ViewAttributes {
        let frame: CGRect = .mockRandom()
        return .init(
            frame: frame,
            clip: frame,
            backgroundColor: UIColor.mockRandom().cgColor,
            layerBorderColor: UIColor.mockRandom().cgColor,
            layerBorderWidth: .mockRandom(min: 0, max: 5),
            layerCornerRadius: .mockRandom(min: 0, max: 5),
            alpha: .mockRandom(min: 0, max: 1),
            isHidden: .mockRandom(),
            intrinsicContentSize: .mockRandom(),
            overrides: .mockAny()
        )
    }

    /// Partial mock, not guaranteeing consistency of returned `ViewAttributes`.
    static func mockWith(
        frame: CGRect = .mockAny(),
        clip: CGRect = .mockAny(),
        backgroundColor: CGColor? = .mockAny(),
        layerBorderColor: CGColor? = .mockAny(),
        layerBorderWidth: CGFloat = .mockAny(),
        layerCornerRadius: CGFloat = .mockAny(),
        alpha: CGFloat = .mockAny(),
        isHidden: Bool = .mockAny(),
        intrinsicContentSize: CGSize = .mockAny(),
        overrides: PrivacyOverrides = .mockAny()
    ) -> ViewAttributes {
        return .init(
            frame: frame,
            clip: clip,
            backgroundColor: backgroundColor,
            layerBorderColor: layerBorderColor,
            layerBorderWidth: layerBorderWidth,
            layerCornerRadius: layerCornerRadius,
            alpha: alpha,
            isHidden: isHidden,
            intrinsicContentSize: intrinsicContentSize,
            overrides: overrides
        )
    }

    /// A fixture for mocking consistent state in `ViewAttributes`.
    enum Fixture: CaseIterable {
        static var allCases: [DatadogSessionReplay.ViewAttributes.Fixture] = [
            .invisible,
            .visible(.noAppearance),
            .visible(.someAppearance),
            .opaque
        ]

        enum Apperance: CaseIterable {
            // Some appearance.
            case someAppearance
            // No appearance (e.g. all colors are fully transparent).
            case noAppearance
        }
        /// A view that is not visible.
        case invisible
        /// A view that is visible.
        case visible(_ apperance: Apperance = .someAppearance)
        /// A view that is opaque.
        case opaque
    }

    /// Partial mock, guaranteeing consistency of returned `ViewAttributes`.
    static func mock(fixture: Fixture) -> ViewAttributes {
        var frame: CGRect
        var backgroundColor: CGColor?
        var layerBorderColor: CGColor?
        var layerBorderWidth: CGFloat?
        var alpha: CGFloat
        var isHidden: Bool

        // swiftlint:disable opening_brace
        switch fixture {
        case .invisible:
            isHidden = true
            alpha = 0
            frame = .zero
        case .visible(.noAppearance):
            // visible:
            isHidden = false
            alpha = .mockRandom(min: 0.1, max: 1)
            frame = .mockRandom(maxX: 5, maxY: 5, minWidth: 10, minHeight: 10)
            // no appearance:
            oneOrMoreOf([
                { layerBorderWidth = 0 },
                { backgroundColor = UIColor.mockRandomWith(alpha: 0).cgColor }
            ])
        case .visible(.someAppearance):
            // visibile:
            isHidden = false
            alpha = .mockRandom(min: 0.1, max: 1)
            frame = .mockRandom(maxX: 5, maxY: 5, minWidth: 10, minHeight: 10)
            // some appearance:
            oneOrMoreOf([
                {
                    layerBorderWidth = .mockRandom(min: 1, max: 5)
                    layerBorderColor = UIColor.mockRandomWith(alpha: .mockRandom(min: 0.1, max: 1)).cgColor
                },
                { backgroundColor = UIColor.mockRandomWith(alpha: .mockRandom(min: 0.1, max: 1)).cgColor }
            ])
        case .opaque:
            // opaque:
            isHidden = false
            alpha = 1
            frame = .mockRandom(maxX: 5, maxY: 5, minWidth: 10, minHeight: 10)
            backgroundColor = UIColor.mockRandomWith(alpha: 1).cgColor
            layerBorderWidth = .mockRandom(min: 1, max: 5)
            layerBorderColor = UIColor.mockRandomWith(alpha: .mockRandom(min: 0.1, max: 1)).cgColor
        }
        // swiftlint:enable opening_brace

        let mock = ViewAttributes(
            frame: frame,
            clip: frame,
            backgroundColor: backgroundColor,
            layerBorderColor: layerBorderColor,
            layerBorderWidth: layerBorderWidth ?? .mockRandom(min: 1, max: 4),
            layerCornerRadius: .mockRandom(min: 0, max: 4),
            alpha: alpha,
            isHidden: isHidden,
            intrinsicContentSize: frame.size,
            overrides: .mockAny()
        )

        // consistency check:
        switch fixture {
        case .invisible:
            assert(!mock.isVisible)
        case .visible(.noAppearance):
            assert(mock.isVisible && !mock.hasAnyAppearance)
        case .visible(.someAppearance):
            assert(mock.isVisible && mock.hasAnyAppearance)
        case .opaque:
            assert(mock.isVisible && mock.hasAnyAppearance && mock.alpha == 1)
        }

        return mock
    }
}

struct NOPWireframesBuilderMock: NodeWireframesBuilder {
    let wireframeRect: CGRect = .zero

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return []
    }
}

extension NodeSubtreeStrategy: AnyMockable, RandomMockable {
    public static func mockAny() -> NodeSubtreeStrategy {
        return .ignore
    }

    public static func mockRandom() -> NodeSubtreeStrategy {
        let all: [NodeSubtreeStrategy] = [.record, .ignore]
        return all.randomElement()!
    }
}

func mockAnyNodeSemantics() -> NodeSemantics {
    return InvisibleElement.constant
}

func mockRandomNodeSemantics() -> NodeSemantics {
    let all: [NodeSemantics] = [
        UnknownElement.constant,
        InvisibleElement.constant,
        AmbiguousElement(
            nodes: .mockRandom(count: .mockRandom(min: 1, max: 5))
        ),
        SpecificElement(subtreeStrategy: .mockRandom(), nodes: .mockRandom(count: .mockRandom(min: 1, max: 5))),
    ]
    return all.randomElement()!
}

struct ShapeWireframesBuilderMock: NodeWireframesBuilder {
    let wireframeRect: CGRect

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [builder.createShapeWireframe(id: .mockAny(), frame: wireframeRect, clip: wireframeRect)]
    }
}

@_spi(Internal)
extension Node: AnyMockable, RandomMockable {
    public static func mockAny() -> Node {
        return mockWith()
    }

    static func mockWith(
        viewAttributes: ViewAttributes = .mockAny(),
        wireframesBuilder: NodeWireframesBuilder = NOPWireframesBuilderMock()
    ) -> Node {
        return .init(
            viewAttributes: viewAttributes,
            wireframesBuilder: wireframesBuilder
        )
    }

    public static func mockRandom() -> Node {
        return .init(
            viewAttributes: .mockRandom(),
            wireframesBuilder: NOPWireframesBuilderMock()
        )
    }
}

struct MockResource: Resource, AnyMockable, RandomMockable {
    var identifier: String
    var data: Data

    init(identifier: String, data: Data) {
        self.identifier = identifier
        self.data = data
    }

    func calculateIdentifier() -> String {
        return identifier
    }

    func calculateData() -> Data {
        return data
    }

    static func mockAny() -> MockResource {
        return MockResource(identifier: .mockAny(), data: .mockAny())
    }

    static func mockRandom() -> MockResource {
        return MockResource(identifier: . mockRandom(), data: .mockRandom())
    }
}

extension UIImageResource: RandomMockable {
    public static func mockRandom() -> UIImageResource {
        return .init(image: .mockRandom(), tintColor: .mockRandom())
    }
}

extension Array where Element == Resource {
    static func mockAny() -> [Resource] {
        return [MockResource].mockAny()
    }

    static func mockRandom(count: Int = 10) -> [Resource] {
        return [MockResource].mockRandom(count: count)
    }
}

extension SpecificElement {
    static func mockAny() -> SpecificElement {
        SpecificElement(subtreeStrategy: .mockRandom(), nodes: [])
    }

    static func mockWith(
        subtreeStrategy: NodeSubtreeStrategy = .mockAny(),
        nodes: [Node] = .mockAny()
    ) -> SpecificElement {
        SpecificElement(
            subtreeStrategy: subtreeStrategy,
            nodes: nodes
        )
    }
}

internal class TextObfuscatorMock: TextObfuscating {
    var result: (String) -> String = { $0 }

    func mask(text: String) -> String {
        return result(text)
    }
}

internal func mockRandomTextObfuscator() -> TextObfuscating {
    return [NOPTextObfuscator(), SpacePreservingMaskObfuscator(), FixLengthMaskObfuscator()].randomElement()!
}

extension ViewTreeRecordingContext: AnyMockable, RandomMockable {
    public static func mockAny() -> ViewTreeRecordingContext {
        return .mockWith()
    }

    public static func mockRandom() -> ViewTreeRecordingContext {
        let view = UIView.mockRandom()
        return .init(
            recorder: .mockRandom(),
            coordinateSpace: view,
            ids: NodeIDGenerator(),
            webViewCache: .weakObjects(),
            clip: view.bounds
        )
    }

    static func mockWith(
        recorder: Recorder.Context = .mockAny(),
        coordinateSpace: UICoordinateSpace = UIView.mockAny(),
        ids: NodeIDGenerator = NodeIDGenerator(),
        webViewCache: NSHashTable<WKWebView> = .weakObjects(),
        clip: CGRect? = nil
    ) -> ViewTreeRecordingContext {
        return .init(
            recorder: recorder,
            coordinateSpace: coordinateSpace,
            ids: ids,
            webViewCache: webViewCache,
            clip: clip ?? coordinateSpace.bounds
        )
    }
}

class NodeRecorderMock: NodeRecorder {
    var identifier = UUID()
    var queriedViews: Set<UIView> = []
    var queryAttributes: [ViewAttributes] = []
    var queryAttributesByView: [UIView: ViewAttributes] = [:]
    var queryContexts: [ViewTreeRecordingContext] = []
    var queryContextsByView: [UIView: ViewTreeRecordingContext] = [:]
    var resultForView: ((UIView) -> NodeSemantics?)?

    init(resultForView: ((UIView) -> NodeSemantics?)? = nil) {
        self.resultForView = resultForView
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        queriedViews.insert(view)
        queryAttributes.append(attributes)
        queryAttributesByView[view] = attributes
        queryContexts.append(context)
        queryContextsByView[view] = context
        return resultForView?(view)
    }
}

class SessionReplayNodeRecorderMock: SessionReplayNodeRecorder {
    var identifier = UUID()
    var queriedViews: Set<UIView> = []
    var queryContexts: [ViewTreeRecordingContext] = []
    var queryContextsByView: [UIView: ViewTreeRecordingContext] = [:]
    var resultForView: ((UIView) -> NodeSemantics?)?

    init(resultForView: ((UIView) -> NodeSemantics?)? = nil) {
        self.resultForView = resultForView
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        queriedViews.insert(view)
        queryContexts.append(context)
        queryContextsByView[view] = context
        return resultForView?(view)
    }
}

// MARK: - TouchSnapshot Mocks

extension TouchSnapshot: AnyMockable, RandomMockable {
    public static func mockAny() -> TouchSnapshot {
        return .mockWith()
    }

    public static func mockRandom() -> TouchSnapshot {
        return TouchSnapshot(
            date: .mockRandom(),
            touches: .mockRandom()
        )
    }

    static func mockWith(
        date: Date = .mockAny(),
        touches: [Touch] = .mockAny()
    ) -> TouchSnapshot {
        return TouchSnapshot(
            date: date,
            touches: touches
        )
    }
}

extension TouchSnapshot.Touch: AnyMockable, RandomMockable {
    public static func mockAny() -> TouchSnapshot.Touch {
        return .mockWith()
    }

    public static func mockRandom() -> TouchSnapshot.Touch {
        return TouchSnapshot.Touch(
            id: .mockRandom(),
            phase: [.down, .move, .up].randomElement()!,
            date: .mockRandom(),
            position: .mockRandom(),
            touchOverride: nil
        )
    }

    static func mockWith(
        id: TouchIdentifier = .mockAny(),
        phase: TouchSnapshot.TouchPhase = .move,
        date: Date = .mockAny(),
        position: CGPoint = .mockAny()
    ) -> TouchSnapshot.Touch {
        return TouchSnapshot.Touch(
            id: id,
            phase: phase,
            date: date,
            position: position,
            touchOverride: nil
        )
    }
}

// MARK: - Recorder Mocks

extension Recorder.Context: AnyMockable, RandomMockable {
    public static func mockAny() -> Recorder.Context {
        return .mockWith()
    }

    public static func mockRandom() -> Recorder.Context {
        return Recorder.Context(
            textAndInputPrivacy: .mockRandom(),
            imagePrivacy: .mockRandom(),
            touchPrivacy: .mockRandom(),
            rumContext: .mockRandom(),
            date: .mockRandom()
        )
    }

    static func mockWith(
        date: Date = .mockAny(),
        textAndInputPrivacy: TextAndInputPrivacyLevel = .mockAny(),
        imagePrivacy: ImagePrivacyLevel = .mockAny(),
        touchPrivacy: TouchPrivacyLevel = .mockAny(),
        rumContext: RUMContext = .mockAny()
    ) -> Recorder.Context {
        return Recorder.Context(
            textAndInputPrivacy: textAndInputPrivacy,
            imagePrivacy: imagePrivacy,
            touchPrivacy: touchPrivacy,
            rumContext: rumContext,
            date: date
        )
    }

    init(
        textAndInputPrivacy: TextAndInputPrivacyLevel,
        imagePrivacy: ImagePrivacyLevel,
        touchPrivacy: TouchPrivacyLevel,
        rumContext: RUMContext,
        date: Date = Date()
    ) {
        self.init(
            textAndInputPrivacy: textAndInputPrivacy,
            imagePrivacy: imagePrivacy,
            touchPrivacy: touchPrivacy,
            applicationID: rumContext.applicationID,
            sessionID: rumContext.sessionID,
            viewID: rumContext.viewID ?? "",
            viewServerTimeOffset: rumContext.viewServerTimeOffset,
            date: date
        )
    }
}

extension UIApplicationSwizzler: AnyMockable {
    public static func mockAny() -> UIApplicationSwizzler {
        class HandlerMock: UIEventHandler {
            func notify_sendEvent(application: UIApplication, event: UIEvent) {}
        }

        return try! UIApplicationSwizzler(handler: HandlerMock())
    }
}

// MARK: - UIView mocks

/// Creates mocked instance of generic `UIView` subclass and configures its state with provided `attributes`. 
internal func mockUIView<View: UIView>(with attributes: ViewAttributes) -> View {
    let view = View(frame: attributes.frame)

    view.backgroundColor = attributes.backgroundColor.map { UIColor(cgColor: $0) }
    view.layer.borderColor = attributes.layerBorderColor
    view.layer.borderWidth = attributes.layerBorderWidth
    view.layer.cornerRadius = attributes.layerCornerRadius
    view.alpha = attributes.alpha
    view.isHidden = attributes.isHidden

    // Consistency check - to make sure computed properties in `ViewAttributes` captured
    // for mocked view are equal the these from requested `attributes`.
    let expectedAttributes = attributes
    let actualAttributes = ViewAttributes(view: view, frame: view.frame, clip: view.frame, overrides: .mockAny())

    assert(
        actualAttributes.isVisible == expectedAttributes.isVisible,
        """
        The `.isVisible` value in provided `attributes` will be resolved differently for mocked
        view than its original value passed to this function. Make sure that provided attributes
        are consistent and if nothing else in `\(type(of: view))` is not overriding visibility state.
        """
    )

    assert(
        actualAttributes.hasAnyAppearance == expectedAttributes.hasAnyAppearance,
        """
        The `.hasAnyAppearance` value in provided `attributes` will be resolved differently for mocked
        view than its original value passed to this function. Make sure that provided attributes
        are consistent and if nothing else in `\(type(of: view))` is not overriding appearance state.
        """
    )

    assert(
        actualAttributes.isTranslucent == expectedAttributes.isTranslucent,
        """
        The `.isTranslucent` value in provided `attributes` will be resolved differently for mocked
        view than its original value passed to this function. Make sure that provided attributes
        are consistent and if nothing else in `\(type(of: view))` is not overriding translucency state.
        """
    )

    return view
}

extension UIView {
    static func mock(withFixture fixture: ViewAttributes.Fixture) -> Self {
        return mockUIView(with: .mock(fixture: fixture))
    }
}

internal extension Optional where Wrapped == NodeSemantics {
    func expectWireframeBuilders<T: NodeWireframesBuilder>(ofType: T.Type = T.self, file: StaticString = #file, line: UInt = #line) throws -> [T] {
        return try unwrapOrThrow(file: file, line: line).nodes
            .compactMap { $0.wireframesBuilder as? T }
    }

    func expectWireframeBuilder<T: NodeWireframesBuilder>(ofType: T.Type = T.self, file: StaticString = #file, line: UInt = #line) throws -> T {
        let builders: [T] = try expectWireframeBuilders(file: file, line: line)
        XCTAssertEqual(builders.count, 1, "Expected single \(T.self), found none", file: file, line: line)
        return try XCTUnwrap(builders.first, file: file, line: line)
    }
}

extension PrivacyOverrides: AnyMockable, RandomMockable {
    public static func mockAny() -> PrivacyOverrides {
        return mockWith()
    }

    public static func mockRandom() -> PrivacyOverrides {
        return mockWith(
            textAndInputPrivacy: .mockRandom(),
            imagePrivacy: .mockRandom(),
            touchPrivacy: .mockRandom(),
            hide: .mockRandom()
        )
    }

    public static func mockWith(
        textAndInputPrivacy: TextAndInputPrivacyLevel? = nil,
        imagePrivacy: ImagePrivacyLevel? = nil,
        touchPrivacy: TouchPrivacyLevel? = nil,
        hide: Bool? = nil
    ) -> PrivacyOverrides {
        let override = PrivacyOverrides(UIView.mockRandom())
        override.textAndInputPrivacy = textAndInputPrivacy
        override.imagePrivacy = imagePrivacy
        override.touchPrivacy = touchPrivacy
        override.hide = hide
        return override
    }
}
#endif
