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
    /// - Returns: the `NodeID` of queried instance
    func nodeID(view: UIView, nodeRecorder: NodeRecorder) -> NodeID {
        if let currentID = view.nodeID?[nodeRecorder.identifier] {
            return currentID
        } else {
            let id = getNextID()
            if view.nodeID != nil {
                view.nodeID?[nodeRecorder.identifier] = id
            } else {
                view.nodeID = [nodeRecorder.identifier: id]
            }
            return id
        }
    }

    /// Returns multiple `NodeIDs` for given instance of `UIView`.
    /// - Parameter size: the number of IDs
    /// - Parameter view: the `UIView` object
    /// - Returns: an array with given number of `NodeID` values
    func nodeIDs(_ size: Int, view: UIView, nodeRecorder: NodeRecorder) -> [NodeID] {
        if let currentIDs = view.nodeIDs?[nodeRecorder.identifier], currentIDs.count == size {
            return currentIDs
        } else {
            let ids = (0..<size).map { _ in getNextID() }
            if view.nodeIDs != nil {
                view.nodeIDs?[nodeRecorder.identifier] = ids
            } else {
                view.nodeIDs = [nodeRecorder.identifier: ids]
            }
            return ids
        }
    }

    private func getNextID() -> NodeID {
        let nextID = currentID
        currentID = currentID < maxID ? (currentID + 1) : 0
        return nextID
    }
}

// MARK: - UIView tagging

fileprivate var associatedNodeIDKey: UInt8 = 1
fileprivate var associatedNodeIDsKey: UInt8 = 2

private extension UIView {
    var nodeID: [UUID: NodeID]? {
        set { objc_setAssociatedObject(self, &associatedNodeIDKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        get { objc_getAssociatedObject(self, &associatedNodeIDKey) as? [UUID: NodeID] }
    }

    var nodeIDs: [UUID: [NodeID]]? {
        set { objc_setAssociatedObject(self, &associatedNodeIDsKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        get { objc_getAssociatedObject(self, &associatedNodeIDsKey) as? [UUID: [NodeID]] }
    }
}
#endif
