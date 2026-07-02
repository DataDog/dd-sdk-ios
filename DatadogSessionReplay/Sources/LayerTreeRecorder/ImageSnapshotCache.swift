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
    private let contentSnapshots: NSCache<NSNumber, ContentSnapshot>
    private var frameNumber: UInt64 = 0
    private var contentMetadata: [Int64: Metadata] = [:]

    init(
        policy: Policy = .default,
        contentSnapshots: NSCache<NSNumber, ContentSnapshot> = NSCache()
    ) {
        self.policy = .init(
            expirationFrameCount: policy.expirationFrameCount,
            removalIntervalFrameCount: max(1, policy.removalIntervalFrameCount),
            maximumRemovals: max(1, policy.maximumRemovals)
        )
        self.contentSnapshots = contentSnapshots
    }

    func updateFrameNumber(for requests: [ImageSnapshotRequest]) {
        frameNumber &+= 1

        for request in requests {
            contentMetadata[request.replayID]?.lastFrameNumber = frameNumber
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
            bounds: metadata.bounds,
            dependencies: metadata.dependencies
        )
    }

    func setContentSnapshotData(
        _ snapshotData: ContentSnapshotData,
        forReplayID replayID: Int64
    ) {
        contentSnapshots.setObject(snapshotData.snapshot, forKey: replayID as NSNumber)
        contentMetadata[replayID] = .init(
            localRect: snapshotData.localRect,
            bounds: snapshotData.bounds,
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

    func removeContentSnapshotData(forReplayID replayID: Int64) {
        contentMetadata.removeValue(forKey: replayID)
        contentSnapshots.removeObject(forKey: replayID as NSNumber)
    }

    func removeContentSnapshotData<ReplayIDs: Sequence>(forReplayIDs replayIDs: ReplayIDs) where ReplayIDs.Element == Int64 {
        for replayID in replayIDs {
            removeContentSnapshotData(forReplayID: replayID)
        }
    }

    private func removeExpiredSnapshots() {
        let expiredReplayIDs = contentMetadata.compactMap { replayID, entry in
            frameNumber - entry.lastFrameNumber > policy.expirationFrameCount ? replayID : nil
        }
        .prefix(policy.maximumRemovals)

        removeContentSnapshotData(forReplayIDs: expiredReplayIDs)
    }
}
#endif
