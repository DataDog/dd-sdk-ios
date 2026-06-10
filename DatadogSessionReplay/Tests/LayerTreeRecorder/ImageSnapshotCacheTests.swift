/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Testing
import UIKit

@testable import DatadogSessionReplay

@MainActor
struct ImageSnapshotCacheTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Returns stored snapshot data")
    func returnsStoredSnapshotData() throws {
        // Given
        let cache = ImageSnapshotCache()
        let snapshot = ImageSnapshot.mockAny()
        let snapshotData = ImageSnapshotData.mockAny(
            snapshot: snapshot,
            localRect: CGRect(x: 1, y: 2, width: 3, height: 4),
            bounds: CGRect(x: 5, y: 6, width: 7, height: 8)
        )

        // When
        cache.setSnapshotData(snapshotData, forReplayID: 1)
        let cachedSnapshotData = try #require(cache.snapshotData(forReplayID: 1))

        // Then
        #expect(cachedSnapshotData.snapshot === snapshot)
        #expect(cachedSnapshotData.localRect == snapshotData.localRect)
        #expect(cachedSnapshotData.bounds == snapshotData.bounds)
        #expect(cachedSnapshotData.dependencies == snapshotData.dependencies)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes stored snapshot data")
    func removesStoredSnapshotData() {
        // Given
        let cache = ImageSnapshotCache()
        cache.setSnapshotData(.mockAny(), forReplayID: 1)

        // When
        cache.removeSnapshotData(forReplayID: 1)

        // Then
        #expect(cache.snapshotData(forReplayID: 1) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Drops snapshot data when cached image is evicted")
    func dropsSnapshotDataWhenCachedImageIsEvicted() {
        // Given
        let imageSnapshots = NSCache<NSNumber, ImageSnapshot>()
        let cache = ImageSnapshotCache(imageSnapshots: imageSnapshots)
        cache.setSnapshotData(.mockAny(), forReplayID: 1)

        // When
        imageSnapshots.removeAllObjects()

        // Then
        #expect(cache.snapshotData(forReplayID: 1) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes stored snapshot data for direct content changes")
    func removesStoredSnapshotDataForDirectContentChanges() {
        // Given
        let layer = CALayer()
        let cache = ImageSnapshotCache()
        cache.setSnapshotData(.mockAny(), forReplayID: layer.replayID)
        let changeset = CALayerChangeset.mockChange(for: layer, aspects: .display)

        // When
        cache.removeSnapshotDataForChanges(in: changeset)

        // Then
        #expect(cache.snapshotData(forReplayID: layer.replayID) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes stored snapshot data when dependency changes")
    func removesStoredSnapshotDataWhenDependencyChanges() {
        // Given
        let owner = CALayer()
        let dependency = CALayer()
        let cache = ImageSnapshotCache()
        cache.setSnapshotData(
            .mockAny(dependencies: [.init(dependency)]),
            forReplayID: owner.replayID
        )
        let changeset = CALayerChangeset.mockChange(for: dependency, aspects: .layout)

        // When
        cache.removeSnapshotDataForChanges(in: changeset)

        // Then
        #expect(cache.snapshotData(forReplayID: owner.replayID) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Keeps stored snapshot data when owner only lays out")
    func keepsStoredSnapshotDataWhenOwnerOnlyLaysOut() {
        // Given
        let owner = CALayer()
        let dependency = CALayer()
        let cache = ImageSnapshotCache()
        cache.setSnapshotData(
            .mockAny(dependencies: [.init(dependency)]),
            forReplayID: owner.replayID
        )
        let changeset = CALayerChangeset.mockChange(for: owner, aspects: .layout)

        // When
        cache.removeSnapshotDataForChanges(in: changeset)

        // Then
        #expect(cache.snapshotData(forReplayID: owner.replayID) != nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Expires snapshot data after unobserved frames")
    func expiresSnapshotDataAfterUnobservedFrames() throws {
        // Given
        let policy = ImageSnapshotCache.Policy(
            expirationFrameCount: 1,
            removalIntervalFrameCount: 1,
            maximumRemovals: 1
        )
        let cache = ImageSnapshotCache(policy: policy)
        let snapshot = ImageSnapshot.mockAny()
        cache.setSnapshotData(.mockAny(snapshot: snapshot), forReplayID: 1)

        // When
        cache.updateFrameNumber(for: [1])
        cache.updateFrameNumber(for: [])

        // Then
        let cachedSnapshot = try #require(cache.snapshotData(forReplayID: 1)?.snapshot)
        #expect(cachedSnapshot === snapshot)

        // When
        cache.updateFrameNumber(for: [])

        // Then
        #expect(cache.snapshotData(forReplayID: 1) == nil)
    }
}

#endif
