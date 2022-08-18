/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CoreGraphics
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
        root: ViewTreeSnapshot.Node = .mockAny()
    ) -> ViewTreeSnapshot {
        return ViewTreeSnapshot(
            date: date,
            root: root
        )
    }
}

extension ViewTreeSnapshot.Node: AnyMockable, RandomMockable {
    static func mockAny() -> ViewTreeSnapshot.Node {
        return mockWith()
    }

    static func mockWith(
        children: [ViewTreeSnapshot.Node] = [],
        frame: ViewTreeSnapshot.Node.Frame = .mockAny()
    ) -> ViewTreeSnapshot.Node {
        return .init(
            children: children,
            frame: frame
        )
    }

    static func mockRandom() -> ViewTreeSnapshot.Node {
        return mockRandom(maxDepth: 4, maxBreadth: 4)
    }

    static func mockRandom(maxDepth: Int, maxBreadth: Int) -> ViewTreeSnapshot.Node {
        mockRandom(
            depth: .random(in: 0..<maxDepth),
            breadth: .random(in: 0..<maxBreadth)
        )
    }

    /// Generates random view snapshot.
    /// - Parameters:
    ///   - depth: number of levels of nested snapshots
    ///   - breadth: number of child snapshots in each nested snapshot (except the last level determined by `depth` which has no childs)
    /// - Returns: randomized snapshot
    static func mockRandom(depth: Int, breadth: Int) -> ViewTreeSnapshot.Node {
        return mockWith(
            children: depth <= 0 ? [] : (0..<breadth).map { _ in mockRandom(depth: depth - 1, breadth: breadth) },
            frame: .mockRandom()
        )
    }
}

extension ViewTreeSnapshot.Node.Frame: AnyMockable, RandomMockable {
    static func mockAny() -> ViewTreeSnapshot.Node.Frame {
        return .init(x: 0, y: 0, width: 420, height: 420)
    }

    static func mockRandom() -> ViewTreeSnapshot.Node.Frame {
        return .init(
            x: .mockRandom(min: -1_000, max: 1_000),
            y: .mockRandom(min: -1_000, max: 1_000),
            width: .mockRandom(min: 0, max: 1_000),
            height: .mockRandom(min: 0, max: 1_000)
        )
    }
}
