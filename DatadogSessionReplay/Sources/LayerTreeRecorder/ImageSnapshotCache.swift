/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// Cache of layer image snapshots.
///
/// Stores rendered snapshots across image snapshot passes and keeps the render
/// metadata needed to decide when a cached snapshot can be reused.
@available(iOS 13.0, tvOS 13.0, *)
internal final class ImageSnapshotCache {
    struct Policy {
        let expirationFrameCount: UInt64
        let removalIntervalFrameCount: UInt64
        let maximumRemovals: Int

        static let `default` = Self(
            expirationFrameCount: 300,
            removalIntervalFrameCount: 10,
            maximumRemovals: 128
        )
    }

    private struct Metadata {
        let localRect: CGRect
        let bounds: CGRect
        let dependencies: [CALayerReference]
        var lastFrameNumber: UInt64
    }

    private let policy: Policy
    private let imageSnapshots: NSCache<NSNumber, ImageSnapshot>
    private var frameNumber: UInt64 = 0
    private var metadata: [Int64: Metadata] = [:]

    init(
        policy: Policy = .default,
        imageSnapshots: NSCache<NSNumber, ImageSnapshot> = NSCache()
    ) {
        self.policy = .init(
            expirationFrameCount: policy.expirationFrameCount,
            removalIntervalFrameCount: max(1, policy.removalIntervalFrameCount),
            maximumRemovals: max(1, policy.maximumRemovals)
        )
        self.imageSnapshots = imageSnapshots
    }

    func updateFrameNumber(for replayIDs: [Int64]) {
        frameNumber &+= 1

        for replayID in replayIDs {
            metadata[replayID]?.lastFrameNumber = frameNumber
        }

        if frameNumber.isMultiple(of: policy.removalIntervalFrameCount) {
            removeExpiredSnapshots()
        }
    }

    func snapshotData(forReplayID replayID: Int64) -> ImageSnapshotData? {
        guard let metadata = metadata[replayID] else {
            return nil
        }

        guard let snapshot = imageSnapshots.object(forKey: replayID as NSNumber) else {
            self.metadata.removeValue(forKey: replayID)
            return nil
        }

        return .init(
            snapshot: snapshot,
            localRect: metadata.localRect,
            bounds: metadata.bounds
        )
    }

    func setSnapshotData(
        _ snapshotData: ImageSnapshotData,
        forReplayID replayID: Int64,
        dependencies: [CALayerReference] = []
    ) {
        imageSnapshots.setObject(snapshotData.snapshot, forKey: replayID as NSNumber)
        metadata[replayID] = .init(
            localRect: snapshotData.localRect,
            bounds: snapshotData.bounds,
            dependencies: dependencies,
            lastFrameNumber: frameNumber
        )
    }

    @MainActor
    func removeSnapshotDataForChanges(in changeset: CALayerChangeset) {
        var replayIDs = Set<Int64>()

        for change in changeset.contentChanges {
            if let replayID = change.layer.resolve()?.replayID {
                replayIDs.insert(replayID)
            }
        }

        for (replayID, metadata) in metadata where changeset.hasChanges(for: metadata.dependencies) {
            replayIDs.insert(replayID)
        }

        removeSnapshotData(forReplayIDs: replayIDs)
    }

    func removeSnapshotData(forReplayID replayID: Int64) {
        metadata.removeValue(forKey: replayID)
        imageSnapshots.removeObject(forKey: replayID as NSNumber)
    }

    func removeSnapshotData<ReplayIDs: Sequence>(forReplayIDs replayIDs: ReplayIDs) where ReplayIDs.Element == Int64 {
        for replayID in replayIDs {
            removeSnapshotData(forReplayID: replayID)
        }
    }

    private func removeExpiredSnapshots() {
        let expiredReplayIDs = metadata.compactMap { replayID, entry in
            frameNumber - entry.lastFrameNumber > policy.expirationFrameCount ? replayID : nil
        }
        .prefix(policy.maximumRemovals)

        removeSnapshotData(forReplayIDs: expiredReplayIDs)
    }
}
#endif
