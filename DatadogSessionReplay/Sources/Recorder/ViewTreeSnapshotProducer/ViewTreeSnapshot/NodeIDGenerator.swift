/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

/// Single unique ID of a view in view-tree hierarchy.
/// It is used to mark `UIViews` which correspond to single wireframe in the replay.
internal typealias NodeID = Int64

/// Manages `NodeIDs` for `UIView` instances.
///
/// Each `UIView` can be assigned one or more unique IDs. All IDs are linked to `UIView` lifespans, so querying
/// IDs for the same instance of `UIView` will always give the same values.
///
/// **Note**: All `NodeIDGenerator` APIs must be called on the main thread.
internal final class NodeIDGenerator {
    /// Cache of generated node IDs for given `UIView` /  `NodeRecorder` pairs.
    private var ids = Cache<String, [NodeID]>(maximumEntryCount: 10_000)
    /// Upper limit for generated IDs.
    /// After `currentID` reaches this limit, it will start from `0`.
    private let maxID: NodeID
    /// Tracks next `NodeID` to assign.
    private var currentID: NodeID

    init(currentID: NodeID = 0, maxID: NodeID = .max) {
        self.currentID = currentID
        self.maxID = maxID
    }

    /// Returns single `NodeID` for given instance of `UIView`.
    /// - Parameter view: the `UIView` object
    /// - Parameter nodeRecorder: the `NodeRecorder` object
    /// - Returns: the `NodeID` of queried instance
    func nodeID(view: UIView, nodeRecorder: NodeRecorder) -> NodeID {
        let key = nodeRecorder.identifier.uuidString + String(view.hash)
        if let nodeID = ids[key]?.first {
            return nodeID
        } else {
            let nodeID = getNextID()
            ids[key] = [nodeID]
            return nodeID
        }
    }

    /// Returns multiple `NodeIDs` for given instance of `UIView`.
    /// - Parameter size: the number of IDs
    /// - Parameter view: the `UIView` object
    /// - Parameter nodeRecorder: the `NodeRecorder` object
    /// - Returns: an array with given number of `NodeID` values
    func nodeIDs(_ size: Int, view: UIView, nodeRecorder: NodeRecorder) -> [NodeID] {
        let key = nodeRecorder.identifier.uuidString + String(view.hash) + String(size)
        if let nodeIDs = ids[key] {
            return nodeIDs
        } else {
            let nodeIDs = (0..<size).map { _ in getNextID() }
            ids[key] = nodeIDs
            return nodeIDs
        }
    }

    private func getNextID() -> NodeID {
        let nextID = currentID
        currentID = currentID < maxID ? (currentID + 1) : 0
        return nextID
    }
}
#endif
