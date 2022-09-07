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
    static func mockAny() -> ViewAttributes {
        return mockWith()
    }

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
            coordinateSpace: UIView.mockRandom()
        )
    }

    static func mockWith(
        coordinateSpace: UICoordinateSpace = UIView.mockAny()
    ) -> ViewTreeSnapshotBuilder.Context {
        return .init(
            coordinateSpace: coordinateSpace
        )
    }
}
