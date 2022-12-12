/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CoreGraphics

/// Flattens VTS received from `Recorder` by transforming its tree-structure of nodes into array of nodes.
///
/// Flattening includes removal of nodes that are invisible because of being covered by other nodes displayed
/// closer to the screen surface.
internal struct NodesFlattener {
    /// This current implementation is greedy and works in `O(n*log(n))`, wheares `O(n)` is possible.
    /// TODO: RUMM-2461 Improve flattening performance.
    func flattenNodes(in snapshot: ViewTreeSnapshot) -> [Node] {
        var flattened: [Node] = []

        dfsVisit(startingFrom: snapshot.root) { nextNode in
            // Skip invisible nodes:
            if !(nextNode.semantics is InvisibleElement) {
                // When accepting nodes, remove ones that are covered by another opaque node:
                flattened = flattened.compactMap { previousNode in
                    let previousFrame = previousNode.semantics.wireframesBuilder?.wireframeRect ?? .zero
                    let nextFrame = nextNode.semantics.wireframesBuilder?.wireframeRect ?? .zero

                    // Drop previous node when:
                    let dropPreviousNode = nextFrame.contains(previousFrame) // its rect is fully covered by the next node
                        && nextNode.viewAttributes.hasAnyAppearance // and the next node brings something visual
                        && !nextNode.viewAttributes.isTranslucent // and the next node is opaque

                    return dropPreviousNode ? nil : previousNode
                }

                flattened.append(nextNode)
            }
        }

        return flattened
    }

    private func dfsVisit(startingFrom node: Node, visit: (Node) -> Void) {
        visit(node)
        node.children.forEach { child in
            dfsVisit(startingFrom: child, visit: visit)
        }
    }
}
