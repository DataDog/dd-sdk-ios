/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import TestUtilities
import Testing
import UIKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct ImageSnapshotCacheTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Returns stored snapshot data")
    func returnsStoredSnapshotData() throws {
        // Given
        let cache = ImageSnapshotCache()
        let snapshot = ContentSnapshot.mockAny()
        let snapshotData = ContentSnapshotData.mockAny(
            snapshot: snapshot,
            localRect: CGRect(x: 1, y: 2, width: 3, height: 4),
            bounds: CGRect(x: 5, y: 6, width: 7, height: 8),
            renderBounds: CGRect(x: 2, y: 3, width: 5, height: 6)
        )

        // When
        cache.setContentSnapshotData(snapshotData, forReplayID: 1)
        let cachedSnapshotData = try #require(cache.contentSnapshotData(forReplayID: 1))

        // Then
        #expect(cachedSnapshotData.snapshot === snapshot)
        #expect(cachedSnapshotData.localRect == snapshotData.localRect)
        #expect(cachedSnapshotData.renderBounds == snapshotData.renderBounds)
        #expect(cachedSnapshotData.bounds == snapshotData.bounds)
        #expect(cachedSnapshotData.dependencies == snapshotData.dependencies)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes stored snapshot data")
    func removesStoredSnapshotData() {
        // Given
        let cache = ImageSnapshotCache()
        cache.setContentSnapshotData(.mockAny(), forReplayID: 1)

        // When
        cache.removeContentSnapshotData(forReplayID: 1)

        // Then
        #expect(cache.contentSnapshotData(forReplayID: 1) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Returns stored mask snapshot data")
    func returnsStoredMaskSnapshotData() throws {
        // Given
        let cache = ImageSnapshotCache()
        let snapshot = MaskSnapshot.mockAny()
        let snapshotData = MaskSnapshotData.mockAny(
            snapshot: snapshot,
            bounds: CGRect(x: 1, y: 2, width: 3, height: 4),
            frame: CGRect(x: 5, y: 6, width: 7, height: 8)
        )

        // When
        cache.setMaskSnapshotData(snapshotData, forReplayID: 1)
        let cachedSnapshotData = try #require(cache.maskSnapshotData(forReplayID: 1))

        // Then
        #expect(cachedSnapshotData.snapshot === snapshot)
        #expect(cachedSnapshotData.bounds == snapshotData.bounds)
        #expect(cachedSnapshotData.frame == snapshotData.frame)
        #expect(cachedSnapshotData.dependencies == snapshotData.dependencies)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes stored mask snapshot data")
    func removesStoredMaskSnapshotData() {
        // Given
        let cache = ImageSnapshotCache()
        cache.setMaskSnapshotData(.mockAny(), forReplayID: 1)

        // When
        cache.removeMaskSnapshotData(forReplayID: 1)

        // Then
        #expect(cache.maskSnapshotData(forReplayID: 1) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Drops snapshot data when cached image is evicted")
    func dropsSnapshotDataWhenCachedImageIsEvicted() {
        // Given
        let imageSnapshots = NSCache<NSNumber, ContentSnapshot>()
        let cache = ImageSnapshotCache(contentSnapshots: imageSnapshots)
        cache.setContentSnapshotData(.mockAny(), forReplayID: 1)

        // When
        imageSnapshots.removeAllObjects()

        // Then
        #expect(cache.contentSnapshotData(forReplayID: 1) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes stored snapshot data for direct content changes")
    func removesStoredSnapshotDataForDirectContentChanges() {
        // Given
        let layer = CALayer()
        let cache = ImageSnapshotCache()
        cache.setContentSnapshotData(.mockAny(), forReplayID: layer.replayID)
        let changeset = CALayerChangeset.mockChange(for: layer, aspects: .display)

        // When
        cache.removeContentSnapshotDataForChanges(in: changeset)

        // Then
        #expect(cache.contentSnapshotData(forReplayID: layer.replayID) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes stored snapshot data when dependency changes")
    func removesStoredSnapshotDataWhenDependencyChanges() {
        // Given
        let owner = CALayer()
        let dependency = CALayer()
        let cache = ImageSnapshotCache()
        cache.setContentSnapshotData(
            .mockAny(dependencies: [.init(dependency)]),
            forReplayID: owner.replayID
        )
        let changeset = CALayerChangeset.mockChange(for: dependency, aspects: .layout)

        // When
        cache.removeContentSnapshotDataForChanges(in: changeset)

        // Then
        #expect(cache.contentSnapshotData(forReplayID: owner.replayID) == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Keeps stored snapshot data when owner only lays out")
    func keepsStoredSnapshotDataWhenOwnerOnlyLaysOut() {
        // Given
        let owner = CALayer()
        let dependency = CALayer()
        let cache = ImageSnapshotCache()
        cache.setContentSnapshotData(
            .mockAny(dependencies: [.init(dependency)]),
            forReplayID: owner.replayID
        )
        let changeset = CALayerChangeset.mockChange(for: owner, aspects: .layout)

        // When
        cache.removeContentSnapshotDataForChanges(in: changeset)

        // Then
        #expect(cache.contentSnapshotData(forReplayID: owner.replayID) != nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes stored mask snapshot data when dependency changes")
    func removesStoredMaskSnapshotDataWhenDependencyChanges() {
        // Given
        let mask = CALayer()
        let dependency = CALayer()
        let cache = ImageSnapshotCache()
        cache.setMaskSnapshotData(
            .mockAny(dependencies: [.init(mask), .init(dependency)]),
            forReplayID: mask.replayID
        )
        let changeset = CALayerChangeset.mockChange(for: dependency, aspects: .layout)

        // When
        cache.removeMaskSnapshotDataForChanges(in: changeset)

        // Then
        #expect(cache.maskSnapshotData(forReplayID: mask.replayID) == nil)
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
        let layer = CALayer()
        let snapshot = ContentSnapshot.mockAny()
        cache.setContentSnapshotData(.mockAny(snapshot: snapshot), forReplayID: layer.replayID)
        let request = ImageSnapshotRequest.content(
            ContentSnapshotRequest(
                replayID: layer.replayID,
                layer: CALayerReference(layer),
                layerClass: type(of: layer),
                delegateClass: nil,
                hasLayerSemantics: true,
                bounds: layer.bounds,
                geometry: .init(
                    renderBounds: layer.bounds,
                    localRect: layer.bounds,
                    frame: layer.frame
                ),
                isOpaque: layer.isOpaque,
                hasContents: false,
                dependencies: [],
                hasChanges: false,
                textAndInputPrivacyLevel: .maskAll,
                imagePrivacyLevel: .maskAll,
                previousSnapshotData: nil
            )
        )

        // When
        cache.updateFrameNumber(for: [request])
        cache.updateFrameNumber(for: [])

        // Then
        let cachedSnapshot = try #require(cache.contentSnapshotData(forReplayID: layer.replayID)?.snapshot)
        #expect(cachedSnapshot === snapshot)

        // When
        cache.updateFrameNumber(for: [])

        // Then
        #expect(cache.contentSnapshotData(forReplayID: layer.replayID) == nil)
    }
}
#endif
