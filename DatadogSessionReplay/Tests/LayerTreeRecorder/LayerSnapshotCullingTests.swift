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
        #expect(!Fixtures.snapshot(backgroundColor: opaque, cornerRadius: 8).isOpaque)
        #expect(!Fixtures.snapshot(backgroundColor: opaque, hasMask: true).isOpaque)
        #expect(!Fixtures.snapshot(isAxisAligned: false, backgroundColor: opaque).isOpaque)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredBasicCases() {
        #expect([LayerSnapshot]().removingObscured().isEmpty)
        #expect([Fixtures.opaqueSnapshot(replayID: 1)].removingObscured().count == 1)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingObscuredRemovesFullyObscuredLayers() {
        // given
        let bottom = Fixtures.opaqueSnapshot(replayID: 1)
        let middle = Fixtures.opaqueSnapshot(replayID: 2)
        let top = Fixtures.opaqueSnapshot(replayID: 3)

        // when
        let result = [bottom, middle, top].removingObscured()

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
        let result = [back, front].removingObscured()

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
        let result = [left, right].removingObscured()

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
        let result = [layer1, layer2, layer3].removingObscured()

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
        let result = [back, front].removingObscured()

        // then
        #expect(result.map(\.replayID) == [1, 2])
    }
}
#endif
