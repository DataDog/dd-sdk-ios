/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Testing
import QuartzCore

@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshotTests.Fixtures {
    static let viewportRect = CGRect(x: 0, y: 0, width: 100, height: 100)

    static func opaqueSnapshot(
        replayID: Int64 = 0,
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    ) -> LayerSnapshot {
        snapshot(
            replayID: replayID,
            frame: frame,
            opacity: 1.0,
            backgroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1.0),
            hasContents: true
        )
    }
}

extension LayerSnapshotTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func isOpaque() {
        let opaque = CGColor(red: 1, green: 0, blue: 0, alpha: 1.0)
        let translucent = CGColor(red: 1, green: 0, blue: 0, alpha: 0.5)

        #expect(Fixtures.snapshot(backgroundColor: opaque).isOpaque)
        #expect(!Fixtures.snapshot(backgroundColor: translucent).isOpaque)
        #expect(!Fixtures.snapshot(backgroundColor: nil).isOpaque)
        #expect(!Fixtures.snapshot(opacity: 0.9, backgroundColor: opaque).isOpaque)
        #expect(!Fixtures.snapshot(opacity: 1.0, resolvedOpacity: 0.9, backgroundColor: opaque).isOpaque)
        #expect(!Fixtures.snapshot(backgroundColor: opaque, cornerRadius: 8).isOpaque)
        #expect(!Fixtures.snapshot(backgroundColor: opaque, hasMask: true).isOpaque)
        #expect(!Fixtures.snapshot(isAxisAligned: false, backgroundColor: opaque).isOpaque)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredReturnsEmptyForEmptyInput() {
        // given
        let snapshots: [LayerSnapshot] = []

        // when
        let result = snapshots.removingObscured(in: Fixtures.viewportRect)

        // then
        #expect(result.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredKeepsSingleLayer() {
        // given
        let snapshots = [Fixtures.opaqueSnapshot(replayID: 1)]

        // when
        let result = snapshots.removingObscured(in: Fixtures.viewportRect)

        // then
        #expect(result.count == 1)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredRemovesFullyObscuredLayers() {
        // given
        let bottom = Fixtures.opaqueSnapshot(replayID: 1)
        let middle = Fixtures.opaqueSnapshot(replayID: 2)
        let top = Fixtures.opaqueSnapshot(replayID: 3)

        // when
        let result = [bottom, middle, top].removingObscured(in: Fixtures.viewportRect)

        // then
        #expect(result.map(\.replayID) == [3])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredKeepsPartiallyObscuredLayers() {
        // given
        let back = Fixtures.opaqueSnapshot(replayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let front = Fixtures.opaqueSnapshot(replayID: 2, frame: CGRect(x: 50, y: 0, width: 100, height: 100))

        // when
        let result = [back, front].removingObscured(in: Fixtures.viewportRect)

        // then
        #expect(result.count == 2)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredKeepsNonOverlappingLayers() {
        // given
        let left = Fixtures.opaqueSnapshot(replayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let right = Fixtures.opaqueSnapshot(replayID: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100))

        // when
        let result = [left, right].removingObscured(in: Fixtures.viewportRect)

        // then
        #expect(result.count == 2)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredPreservesOrder() {
        // given
        let layer1 = Fixtures.opaqueSnapshot(replayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let layer2 = Fixtures.opaqueSnapshot(replayID: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        let layer3 = Fixtures.opaqueSnapshot(replayID: 3, frame: CGRect(x: 200, y: 0, width: 100, height: 100))

        // when
        let result = [layer1, layer2, layer3].removingObscured(in: Fixtures.viewportRect)

        // then
        #expect(result.map(\.replayID) == [1, 2, 3])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredUsesClipRect() {
        // given
        let back = Fixtures.opaqueSnapshot(replayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let front = Fixtures.snapshot(
            replayID: 2,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            clipRect: CGRect(x: 0, y: 0, width: 50, height: 100),
            opacity: 1.0,
            backgroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1.0),
            hasContents: true
        )

        // when
        let result = [back, front].removingObscured(in: Fixtures.viewportRect)

        // then
        #expect(result.map(\.replayID) == [1, 2])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredDropsSnapshotsWithoutVisibleFrame() {
        // given
        let snapshot = Fixtures.snapshot(
            replayID: 1,
            frame: CGRect(x: 200, y: 0, width: 100, height: 100),
            clipRect: Fixtures.viewportRect,
            opacity: 1.0,
            backgroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1.0),
            hasContents: true
        )

        // when
        let result = [snapshot].removingObscured(in: Fixtures.viewportRect)

        // then
        #expect(result.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredUsesGlobalIndexBucketForLargeOpaqueFrames() {
        // given
        let viewportRect = CGRect(x: 0, y: 0, width: 100, height: 1_000)
        let back = Fixtures.opaqueSnapshot(replayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        // This frame spans > 8 bands (band height is 64), so it should go to the global bucket
        let front = Fixtures.opaqueSnapshot(replayID: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 900))

        // when
        let result = [back, front].removingObscured(in: viewportRect)

        // then
        #expect(result.map(\.replayID) == [2])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredKeepsBackgroundWhenFrontSnapshotHasTranslucentAncestor() {
        // given
        let back = Fixtures.opaqueSnapshot(replayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let front = Fixtures.snapshot(
            replayID: 2,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            opacity: 1.0,
            resolvedOpacity: 0.5,
            backgroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1.0),
            hasContents: true
        )

        // when
        let result = [back, front].removingObscured(in: Fixtures.viewportRect)

        // then
        #expect(result.map(\.replayID) == [1, 2])
    }
}
#endif
