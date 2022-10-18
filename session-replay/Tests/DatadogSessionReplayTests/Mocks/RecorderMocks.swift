/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit
@testable import DatadogSessionReplay

// MARK: - Equatable conformances

extension ViewTreeSnapshot: EquatableInTests {}

// MARK: - Mocking extensions

extension ViewTreeSnapshot: AnyMockable, RandomMockable {
    static func mockAny() -> ViewTreeSnapshot {
        return mockWith()
    }

    static func mockRandom() -> ViewTreeSnapshot {
        return ViewTreeSnapshot(
            date: .mockRandom(),
            root: .mockRandom()
        )
    }

    static func mockWith(
        date: Date = .mockAny(),
        root: Node = .mockAny()
    ) -> ViewTreeSnapshot {
        return ViewTreeSnapshot(
            date: date,
            root: root
        )
    }
}

extension ViewAttributes: AnyMockable, RandomMockable {
    /// Placeholder mock, not guaranteeing consistency of returned `ViewAttributes`.
    static func mockAny() -> ViewAttributes {
        return mockWith()
    }

    /// Random mock, not guaranteeing consistency of returned `ViewAttributes`.
    static func mockRandom() -> ViewAttributes {
        return .init(
            frame: .mockRandom(),
            backgroundColor: UIColor.mockRandom().cgColor,
            layerBorderColor: UIColor.mockRandom().cgColor,
            layerBorderWidth: .mockRandom(min: 0, max: 5),
            layerCornerRadius: .mockRandom(min: 0, max: 5),
            alpha: .mockRandom(min: 0, max: 1),
            intrinsicContentSize: .mockRandom(),
            isVisible: .mockRandom(),
            hasAnyAppearance: .mockRandom()
        )
    }

    /// Partial mock, not guaranteeing consistency of returned `ViewAttributes`.
    static func mockWith(
        frame: CGRect = .mockAny(),
        backgroundColor: CGColor? = .mockAny(),
        layerBorderColor: CGColor? = .mockAny(),
        layerBorderWidth: CGFloat = .mockAny(),
        layerCornerRadius: CGFloat = .mockAny(),
        alpha: CGFloat = .mockAny(),
        intrinsicContentSize: CGSize = .mockAny(),
        isVisible: Bool = .mockAny(),
        hasAnyAppearance: Bool = .mockAny()
    ) -> ViewAttributes {
        return .init(
            frame: frame,
            backgroundColor: backgroundColor,
            layerBorderColor: layerBorderColor,
            layerBorderWidth: layerBorderWidth,
            layerCornerRadius: layerCornerRadius,
            alpha: alpha,
            intrinsicContentSize: intrinsicContentSize,
            isVisible: isVisible,
            hasAnyAppearance: hasAnyAppearance
        )
    }

    /// A fixture for mocking consistent state in `ViewAttributes`.
    enum Fixture {
        /// A view that is not visible.
        case invisible
        /// A view that is visible, but has no appearance (e.g. all colors are fully transparent).
        case visibleWithNoAppearance
        /// A view that is visible and has some appearance.
        case visibleWithSomeAppearance
    }

    /// Partial mock, guaranteeing consistency of returned `ViewAttributes`.
    static func mock(fixture: Fixture) -> ViewAttributes {
        let isVisible: Bool
        let hasAnyAppearance: Bool

        switch fixture {
        case .invisible:
            isVisible = false
            hasAnyAppearance = false
        case .visibleWithNoAppearance:
            isVisible = true
            hasAnyAppearance = false
        case .visibleWithSomeAppearance:
            isVisible = true
            hasAnyAppearance = true
        }

        let frame: CGRect = isVisible ? .mockRandom(minWidth: 10, minHeight: 10) : .zero
        return .init(
            frame: frame,
            backgroundColor: hasAnyAppearance ? .mockRandom() : nil,
            layerBorderColor: hasAnyAppearance ? .mockRandom() : nil,
            layerBorderWidth: hasAnyAppearance ? .mockRandom(min: 1, max: 4) : 0,
            layerCornerRadius: .mockRandom(min: 0, max: 4),
            alpha: isVisible ? .mockRandom(min: 0.01, max: 1) : 0,
            intrinsicContentSize: frame.size,
            isVisible: isVisible,
            hasAnyAppearance: hasAnyAppearance
        )
    }
}

struct NOPWireframesBuilderMock: NodeWireframesBuilder {
    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return []
    }
}

func mockAnyNodeSemantics() -> NodeSemantics {
    return InvisibleElement.constant
}

func mockRandomNodeSemantics() -> NodeSemantics {
    let all: [NodeSemantics] = [
        UnknownElement.constant,
        InvisibleElement.constant,
        AmbiguousElement(wireframesBuilder: NOPWireframesBuilderMock()),
        SpecificElement(wireframesBuilder: NOPWireframesBuilderMock()),
    ]
    return all.randomElement()!
}

extension Node: AnyMockable, RandomMockable {
    static func mockAny() -> Node {
        return mockWith()
    }

    static func mockWith(
        viewAttributes: ViewAttributes = .mockAny(),
        semantics: NodeSemantics = InvisibleElement.constant,
        children: [Node] = []
    ) -> Node {
        return .init(
            viewAttributes: viewAttributes,
            semantics: semantics,
            children: children
        )
    }

    static func mockRandom() -> Node {
        return mockRandom(maxDepth: 4, maxBreadth: 4)
    }

    static func mockRandom(maxDepth: Int, maxBreadth: Int) -> Node {
        mockRandom(
            depth: .random(in: 0..<maxDepth),
            breadth: .random(in: 0..<maxBreadth)
        )
    }

    /// Generates random node.
    /// - Parameters:
    ///   - depth: number of levels of nested nodes
    ///   - breadth: number of child nodes in each nested node (except the last level determined by `depth` which has no childs)
    /// - Returns: randomized node
    static func mockRandom(depth: Int, breadth: Int) -> Node {
        return mockWith(
            viewAttributes: .mockRandom(),
            semantics: mockRandomNodeSemantics(),
            children: depth <= 0 ? [] : (0..<breadth).map { _ in mockRandom(depth: depth - 1, breadth: breadth) }
        )
    }
}

extension ViewTreeSnapshotBuilder.Context: AnyMockable, RandomMockable {
    static func mockAny() -> ViewTreeSnapshotBuilder.Context {
        return .mockWith()
    }

    static func mockRandom() -> ViewTreeSnapshotBuilder.Context {
        return .init(
            coordinateSpace: UIView.mockRandom(),
            options: .mockRandom(),
            ids: NodeIDGenerator(),
            textObfuscator: TextObfuscator()
        )
    }

    static func mockWith(
        coordinateSpace: UICoordinateSpace = UIView.mockAny(),
        options: ViewTreeSnapshotOptions = .mockAny(),
        ids: NodeIDGenerator = NodeIDGenerator(),
        textObfuscator: TextObfuscator = TextObfuscator()
    ) -> ViewTreeSnapshotBuilder.Context {
        return .init(
            coordinateSpace: coordinateSpace,
            options: options,
            ids: ids,
            textObfuscator: textObfuscator
        )
    }
}

extension ViewTreeSnapshotOptions: AnyMockable, RandomMockable {
    static func mockAny() -> ViewTreeSnapshotOptions {
        return .mockWith()
    }

    static func mockRandom() -> ViewTreeSnapshotOptions {
        return ViewTreeSnapshotOptions(
            privacy: .mockRandom()
        )
    }

    static func mockWith(
        privacy: SessionReplayPrivacy = .mockAny()
    ) -> ViewTreeSnapshotOptions {
        return ViewTreeSnapshotOptions(
            privacy: privacy
        )
    }
}

extension SessionReplayPrivacy: AnyMockable, RandomMockable {
    static func mockAny() -> SessionReplayPrivacy {
        return .allowAll
    }

    static func mockRandom() -> SessionReplayPrivacy {
        return [
            .allowAll,
            .maskAll
        ].randomElement()!
    }
}

// MARK: - UIView mocks

/// An error indicating inconsistency of `UIView` (or derived) mock.
internal struct UIViewMockException: Error, CustomDebugStringConvertible {
    var debugDescription: String
}

/// Creates mocked instance of generic `UIView` subclass and configures its state with provided `attributes`. 
internal func mockUIView<View: UIView>(with attributes: ViewAttributes) throws -> View {
    let view = View(frame: attributes.frame)

    view.backgroundColor = attributes.backgroundColor.map { UIColor(cgColor: $0) }
    view.layer.borderColor = attributes.layerBorderColor
    view.layer.borderWidth = attributes.layerBorderWidth
    view.layer.cornerRadius = attributes.layerCornerRadius
    view.alpha = attributes.alpha

    // Consistency check - to make sure computed properties in `ViewAttributes` captured
    // for mocked view are equal the these from requested `attributes`.
    let expectedAttributes = attributes
    let actualAttributes = ViewAttributes(frameInRootView: view.frame, view: view)

    guard actualAttributes.isVisible == expectedAttributes.isVisible else {
        throw UIViewMockException(debugDescription: """
        The `.isVisible` value in provided `attributes` will be resolved differently for mocked
        view than its original value passed to this function. Make sure that provided attributes
        are consistent and if nothing else in `\(type(of: view))` is not overriding visibility state.
        """)
    }

    guard actualAttributes.hasAnyAppearance == expectedAttributes.hasAnyAppearance  else {
        throw UIViewMockException(debugDescription: """
        The `.hasAnyAppearance` value in provided `attributes` will be resolved differently for mocked
        view than its original value passed to this function. Make sure that provided attributes
        are consistent and if nothing else in `\(type(of: view))` is not overriding appearance state.
        """)
    }

    return view
}

extension UIView {
    static func mock(withFixture fixture: ViewAttributes.Fixture) throws -> Self {
        return try mockUIView(with: .mock(fixture: fixture))
    }
}
