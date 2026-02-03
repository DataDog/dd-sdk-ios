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
    func flattenNodes(in snapshot: ViewTreeSnapshot) -> [Node] {
        let viewportRect = CGRect(origin: .zero, size: snapshot.viewportSize)
        var flattened: [Node] = []
        var opaqueFrames: [CGRect] = []

        // Process nodes in reverse DFS order (children before parents)
        for node in snapshot.nodes.reversed() {
            let nodeFrame = node.wireframesBuilder.wireframeRect

            // Skip nodes outside viewport
            guard viewportRect.intersects(nodeFrame) else { continue }

            // Skip if occluded by any existing opaque frame
            let isOccluded = opaqueFrames.contains { opaqueFrame in
                opaqueFrame.contains(nodeFrame)
            }

            if !isOccluded {
                flattened.append(node)

                // If this node is opaque and has appearance, it occludes its area
                if node.viewAttributes.hasAnyAppearance && !node.viewAttributes.isTranslucent {
                    opaqueFrames.append(nodeFrame)
                }
            }
        }

        return flattened.reversed()
    }
}
#endif
