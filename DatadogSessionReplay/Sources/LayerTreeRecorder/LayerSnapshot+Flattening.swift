/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshot {
    func flattened() -> [LayerSnapshot] {
        var result: [LayerSnapshot] = []
        flatten(into: &result)
        return result
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshot {
    fileprivate func flatten(into result: inout [LayerSnapshot]) {
        // Add self if it renders content
        if rendersContent {
            var snapshot = self
            snapshot.children = []
            result.append(snapshot)
        }

        // Process children sorted by zPosition
        // NOTE: `sorted` is stable (SE-0372), so equal `zPosition` preserves capture sibling order.
        let sortedChildren = children.sorted {
            $0.zPosition < $1.zPosition
        }

        for snapshot in sortedChildren {
            snapshot.flatten(into: &result)
        }
    }
}
#endif
