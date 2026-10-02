/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

/// Cache of layer image snapshots.
///
/// Stores rendered snapshots across image snapshot passes and keeps the render
/// metadata needed to decide when a cached snapshot can be reused.
internal final class ImageSnapshotCache {
    struct Policy {
        /// Advisory limits in bitmap bytes, excluding associated redacted images and in-flight snapshots.
        let contentCostLimit: Int
        let maskCostLimit: Int
        let expirationFrameCount: UInt64
        let removalIntervalFrameCount: UInt64
        let maximumRemovals: Int

        static let `default` = Self(
            contentCostLimit: 32 * 1_024 * 1_024,
            maskCostLimit: 8 * 1_024 * 1_024,
            expirationFrameCount: 150,
            removalIntervalFrameCount: 10,
            maximumRemovals: 128
        )
    }

    private struct ContentMetadata {
        let localRect: CGRect
        let renderBounds: CGRect
        let bounds: CGRect
        let dependencies: [CALayerReference]
        var lastFrameNumber: UInt64
    }

    private struct MaskMetadata {
        let bounds: CGRect
        let frame: CGRect
        let dependencies: [CALayerReference]
        var lastFrameNumber: UInt64
    }

    private let policy: Policy
    private let contentSnapshots: NSCache<NSNumber, ContentSnapshot>
    private let maskSnapshots: NSCache<NSNumber, MaskSnapshot>
    private var frameNumber: UInt64 = 0
    private var contentMetadata: [Int64: ContentMetadata] = [:]
    private var maskMetadata: [Int64: MaskMetadata] = [:]

    init(
        policy: Policy = .default,
        contentSnapshots: NSCache<NSNumber, ContentSnapshot> = NSCache(),
        maskSnapshots: NSCache<NSNumber, MaskSnapshot> = NSCache()
    ) {
        self.policy = .init(
            contentCostLimit: max(0, policy.contentCostLimit),
            maskCostLimit: max(0, policy.maskCostLimit),
            expirationFrameCount: policy.expirationFrameCount,
            removalIntervalFrameCount: max(1, policy.removalIntervalFrameCount),
            maximumRemovals: max(1, policy.maximumRemovals)
        )
        self.contentSnapshots = contentSnapshots
        self.maskSnapshots = maskSnapshots
        contentSnapshots.totalCostLimit = self.policy.contentCostLimit
        maskSnapshots.totalCostLimit = self.policy.maskCostLimit
    }

    func updateFrameNumber(for requests: [ImageSnapshotRequest]) {
        frameNumber &+= 1

        for request in requests {
            switch request {
            case .content:
                contentMetadata[request.replayID]?.lastFrameNumber = frameNumber
            case .mask:
                maskMetadata[request.replayID]?.lastFrameNumber = frameNumber
            }
        }

        if frameNumber.isMultiple(of: policy.removalIntervalFrameCount) {
            removeExpiredSnapshots()
        }
    }

    func contentSnapshotData(forReplayID replayID: Int64) -> ContentSnapshotData? {
        guard let metadata = contentMetadata[replayID] else {
            return nil
        }

        guard let snapshot = contentSnapshots.object(forKey: replayID as NSNumber) else {
            contentMetadata.removeValue(forKey: replayID)
            return nil
        }

        return .init(
            snapshot: snapshot,
            localRect: metadata.localRect,
            renderBounds: metadata.renderBounds,
            bounds: metadata.bounds,
            dependencies: metadata.dependencies
        )
    }

    func setContentSnapshotData(
        _ snapshotData: ContentSnapshotData,
        forReplayID replayID: Int64
    ) {
        contentSnapshots.setObject(
            snapshotData.snapshot,
            forKey: replayID as NSNumber,
            cost: snapshotData.snapshot.image.bitmapByteCount
        )
        contentMetadata[replayID] = .init(
            localRect: snapshotData.localRect,
            renderBounds: snapshotData.renderBounds,
            bounds: snapshotData.bounds,
            dependencies: snapshotData.dependencies,
            lastFrameNumber: frameNumber
        )
    }

    func maskSnapshotData(forReplayID replayID: Int64) -> MaskSnapshotData? {
        guard let metadata = maskMetadata[replayID] else {
            return nil
        }

        guard let snapshot = maskSnapshots.object(forKey: replayID as NSNumber) else {
            maskMetadata.removeValue(forKey: replayID)
            return nil
        }

        return .init(
            snapshot: snapshot,
            bounds: metadata.bounds,
            frame: metadata.frame,
            dependencies: metadata.dependencies
        )
    }

    func setMaskSnapshotData(
        _ snapshotData: MaskSnapshotData,
        forReplayID replayID: Int64
    ) {
        maskSnapshots.setObject(
            snapshotData.snapshot,
            forKey: replayID as NSNumber,
            cost: snapshotData.snapshot.image.bitmapByteCount
        )
        maskMetadata[replayID] = .init(
            bounds: snapshotData.bounds,
            frame: snapshotData.frame,
            dependencies: snapshotData.dependencies,
            lastFrameNumber: frameNumber
        )
    }

    @MainActor
    func removeContentSnapshotDataForChanges(in changeset: CALayerChangeset) {
        var replayIDs = Set<Int64>()

        for change in changeset.contentChanges {
            if let replayID = change.layer.resolve()?.replayID {
                replayIDs.insert(replayID)
            }
        }

        for (replayID, metadata) in contentMetadata where changeset.hasChanges(for: metadata.dependencies) {
            replayIDs.insert(replayID)
        }

        removeContentSnapshotData(forReplayIDs: replayIDs)
    }

    func removeMaskSnapshotDataForChanges(in changeset: CALayerChangeset) {
        let replayIDs = maskMetadata.compactMap { replayID, metadata in
            changeset.hasChanges(for: metadata.dependencies) ? replayID : nil
        }

        removeMaskSnapshotData(forReplayIDs: replayIDs)
    }

    func removeContentSnapshotData(forReplayID replayID: Int64) {
        contentMetadata.removeValue(forKey: replayID)
        contentSnapshots.removeObject(forKey: replayID as NSNumber)
    }

    func removeContentSnapshotData<ReplayIDs: Sequence>(forReplayIDs replayIDs: ReplayIDs) where ReplayIDs.Element == Int64 {
        for replayID in replayIDs {
            removeContentSnapshotData(forReplayID: replayID)
        }
    }

    func removeMaskSnapshotData(forReplayID replayID: Int64) {
        maskMetadata.removeValue(forKey: replayID)
        maskSnapshots.removeObject(forKey: replayID as NSNumber)
    }

    func removeMaskSnapshotData<ReplayIDs: Sequence>(forReplayIDs replayIDs: ReplayIDs) where ReplayIDs.Element == Int64 {
        for replayID in replayIDs {
            removeMaskSnapshotData(forReplayID: replayID)
        }
    }

    private func removeExpiredSnapshots() {
        let expiredContentReplayIDs = contentMetadata.compactMap { replayID, entry in
            frameNumber - entry.lastFrameNumber > policy.expirationFrameCount ? replayID : nil
        }
        .prefix(policy.maximumRemovals)

        removeContentSnapshotData(forReplayIDs: expiredContentReplayIDs)

        let expiredMaskReplayIDs = maskMetadata.compactMap { replayID, entry in
            frameNumber - entry.lastFrameNumber > policy.expirationFrameCount ? replayID : nil
        }
        .prefix(policy.maximumRemovals)

        removeMaskSnapshotData(forReplayIDs: expiredMaskReplayIDs)
    }
}

extension UIImage {
    /// The size of the backing bitmap in bytes, excluding associated images.
    fileprivate var bitmapByteCount: Int {
        guard let cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}
#endif
