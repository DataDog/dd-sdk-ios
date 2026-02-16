/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Visibility pruning for captured layer snapshots.
//
// This pass removes clearly invisible branches and empty structural containers while
// preserving nodes that can still contribute visible content through themselves or
// descendants.

#if os(iOS)
import Foundation
import CoreGraphics

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshot {
    var isVisible: Bool {
        !isHidden && opacity != 0 && !frame.isEmpty && frame.intersects(clipRect)
    }

    var rendersContent: Bool {
        // Leaf layers are conservatively assumed to render content since
        // they might draw either by subclassing or through their delegate
        children.isEmpty || hasContents || hasVisibleBackgroundColor || hasVisibleBorder
    }

    func removingInvisible() -> LayerSnapshot? {
        guard isVisible else {
            return nil
        }

        let filteredChildren = children.compactMap { $0.removingInvisible() }

        guard rendersContent || !filteredChildren.isEmpty else {
            return nil
        }

        var snapshot = self
        snapshot.children = filteredChildren

        return snapshot
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshot {
    fileprivate var hasVisibleBackgroundColor: Bool {
        (backgroundColor?.alpha ?? 0) > 0
    }

    fileprivate var hasVisibleBorder: Bool {
        borderWidth > 0 && (borderColor?.alpha ?? 0) > 0
    }
}
#endif
