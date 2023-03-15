/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

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
    static var uniqueCounter: UInt8 = 0

    /// Upper limit for generated IDs.
    /// After `currentID` reaches this limit, it will start from `0`.
    private let maxID: NodeID
    /// Tracks next `NodeID` to assign.
    private var currentID: NodeID

    fileprivate var associatedNodeIDKey: UInt8
    fileprivate var associatedNodeIDsKey: UInt8

    init(currentID: NodeID = 0, maxID: NodeID = .max) {
        self.currentID = currentID
        self.maxID = maxID

        NodeIDGenerator.uniqueCounter += 1
        self.associatedNodeIDKey = NodeIDGenerator.uniqueCounter
        NodeIDGenerator.uniqueCounter += 1
        self.associatedNodeIDsKey = NodeIDGenerator.uniqueCounter
    }

    /// Returns single `NodeID` for given instance of `UIView`.
    /// - Parameter view: the `UIView` object
    /// - Returns: the `NodeID` of queried instance
    func nodeID(for view: NSObject) -> NodeID {
        if let currentID = view.getNodeID(&associatedNodeIDKey) {
            return currentID
        } else {
            let id = getNextID()
            view.setNodeID(id, &associatedNodeIDKey)
            return id
        }
    }

    /// Returns multiple `NodeIDs` for given instance of `UIView`.
    /// - Parameter size: the number of IDs
    /// - Parameter view: the `UIView` object
    /// - Returns: an array with given number of `NodeID` values
    func nodeIDs(_ size: Int, for view: NSObject) -> [NodeID] {
        if let currentIDs = view.getNodeIDs(&associatedNodeIDsKey), currentIDs.count == size {
            return currentIDs
        } else {
            let ids = (0..<size).map { _ in getNextID() }
            view.setNodeIDs(ids, &associatedNodeIDsKey)
            return ids
        }
    }

    func getNextID() -> NodeID {
        let nextID = currentID
        currentID = currentID < maxID ? (currentID + 1) : 0
        return nextID
    }
}

// MARK: - UIView tagging

fileprivate var associatedNodeIDKey: UInt8 = 1
fileprivate var associatedNodeIDsKey: UInt8 = 2

fileprivate var associatedNodeAccessibilityIDKey: UInt8 = 3
fileprivate var associatedNodeAccessibilityIDsKey: UInt8 = 4

private extension NSObject {
    func setNodeID(_ newValue: NodeID?, _ key: UnsafeRawPointer) {
        objc_setAssociatedObject(self, key, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func getNodeID(_ key: UnsafeRawPointer) -> NodeID? {
        objc_getAssociatedObject(self, key) as? NodeID
    }

    func setNodeIDs(_ newValue: [NodeID]?, _ key: UnsafeRawPointer) {
        objc_setAssociatedObject(self, key, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func getNodeIDs(_ key: UnsafeRawPointer) -> [NodeID]? {
        objc_getAssociatedObject(self, key) as? [NodeID]
    }
}
