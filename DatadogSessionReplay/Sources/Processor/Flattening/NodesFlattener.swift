/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import CoreGraphics

/// Flattens VTS received from `Recorder` by removing invisible nodes.
///
/// Nodes are invisible if:
/// - they have no appearance (e.g. nodes denoting container views)
/// - they are covered by another opaque nodes (displayed closer to the screen surface).
internal struct NodesFlattener {
    /// This current implementation is greedy and works in `O(n*log(n))`, wheares `O(n)` is possible.
    /// TODO: RUMM-2461 Improve flattening performance.
    func flattenNodes(in snapshot: ViewTreeSnapshot) -> [Node] {
        var flattened: [Node] = []

        for nextNode in snapshot.nodes {
            // When accepting nodes, remove ones that are covered by another opaque node:
            flattened = flattened.compactMap { previousNode in
                let previousFrame = previousNode.wireframesBuilder.wireframeRect
                let nextFrame = nextNode.wireframesBuilder.wireframeRect

                // Drop previous node when:
                let dropPreviousNode = nextFrame.contains(previousFrame) // its rect is fully covered by the next node
                    && nextNode.viewAttributes.hasAnyAppearance // and the next node brings something visual
                    && !nextNode.viewAttributes.isTranslucent // and the next node is opaque

                return dropPreviousNode ? nil : previousNode
            }

            flattened.append(nextNode)
        }

        return flattened
    }
}
#endif
