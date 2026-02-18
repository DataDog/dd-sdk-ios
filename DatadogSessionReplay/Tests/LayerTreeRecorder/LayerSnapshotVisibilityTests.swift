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
    static func snapshot(
        layer: CALayer = .init(),
        replayID: Int64 = 0,
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
        clipRect: CGRect = .infinite,
        zPosition: CGFloat = 0,
        isAxisAligned: Bool = true,
        opacity: Float = 1.0,
        resolvedOpacity: Float? = nil,
        isHidden: Bool = false,
        backgroundColor: CGColor? = nil,
        hasContents: Bool = false,
        cornerRadius: CGFloat = 0,
        borderWidth: CGFloat = 0,
        borderColor: CGColor? = nil,
        hasMask: Bool = false,
        children: [LayerSnapshot] = []
    ) -> LayerSnapshot {
        return LayerSnapshot(
            layer: CALayerReference(layer),
            replayID: replayID,
            pathComponents: ["Test#\(replayID)"],
            frame: frame,
            clipRect: clipRect,
            zPosition: zPosition,
            isAxisAligned: isAxisAligned,
            opacity: opacity,
            resolvedOpacity: resolvedOpacity ?? opacity,
            isHidden: isHidden,
            backgroundColor: backgroundColor,
            hasContents: hasContents,
            cornerRadius: cornerRadius,
            borderWidth: borderWidth,
            borderColor: borderColor,
            masksToBounds: false,
            hasMask: hasMask,
            children: children
        )
    }
}

extension LayerSnapshotTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func isVisible() {
        #expect(Fixtures.snapshot().isVisible)
        #expect(!Fixtures.snapshot(isHidden: true).isVisible)
        #expect(!Fixtures.snapshot(opacity: 0).isVisible)
        #expect(!Fixtures.snapshot(frame: CGRect(x: 0, y: 0, width: 0, height: 50)).isVisible)
        #expect(!Fixtures.snapshot(frame: CGRect(x: 0, y: 0, width: 100, height: 0)).isVisible)
        #expect(
            !Fixtures.snapshot(
                frame: CGRect(x: 200, y: 200, width: 50, height: 50),
                clipRect: CGRect(x: 0, y: 0, width: 100, height: 100)
            ).isVisible
        )
        #expect(
            Fixtures.snapshot(
                frame: CGRect(x: 50, y: 50, width: 100, height: 100),
                clipRect: CGRect(x: 0, y: 0, width: 100, height: 100)
            ).isVisible
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func rendersContent() {
        #expect(Fixtures.snapshot().rendersContent)
        #expect(
            !Fixtures.snapshot(
                children: [Fixtures.snapshot(hasContents: true)]
            ).rendersContent
        )
        #expect(
            Fixtures.snapshot(
                hasContents: true,
                children: [Fixtures.snapshot(hasContents: true)]
            ).rendersContent
        )
        #expect(
            Fixtures.snapshot(
                backgroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                children: [Fixtures.snapshot(hasContents: true)]
            ).rendersContent
        )
        #expect(
            !Fixtures.snapshot(
                backgroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 0),
                children: [Fixtures.snapshot(hasContents: true)]
            ).rendersContent
        )
        #expect(
            Fixtures.snapshot(
                borderWidth: 2,
                borderColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                children: [Fixtures.snapshot(hasContents: true)]
            ).rendersContent
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingInvisibleFiltersInvisibleSnapshots() {
        #expect(Fixtures.snapshot(isHidden: true).removingInvisible() == nil)
        #expect(Fixtures.snapshot().removingInvisible() != nil)
        #expect(Fixtures.snapshot(hasContents: true).removingInvisible()?.hasContents == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingInvisibleFiltersChildren() {
        // given
        let visibleChild = Fixtures.snapshot(replayID: 1, hasContents: true)
        let hiddenChild = Fixtures.snapshot(replayID: 2, isHidden: true, hasContents: true)
        let parent = Fixtures.snapshot(children: [visibleChild, hiddenChild])

        // when
        let result = parent.removingInvisible()

        // then
        #expect(result?.children.count == 1)
        #expect(result?.children[0].replayID == 1)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingInvisiblePrunesHiddenBranches() {
        // given
        let grandchild = Fixtures.snapshot(hasContents: true)
        let hiddenParent = Fixtures.snapshot(isHidden: true, children: [grandchild])
        let root = Fixtures.snapshot(hasContents: true, children: [hiddenParent])

        // when
        let result = root.removingInvisible()

        // then
        #expect(result?.children.isEmpty == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingInvisiblePrunesEmptyContainers() {
        // given
        let hiddenChild = Fixtures.snapshot(isHidden: true, hasContents: true)
        let parent = Fixtures.snapshot(children: [hiddenChild])

        // then
        #expect(parent.removingInvisible() == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func removingInvisiblePreservesDeepVisibleBranch() {
        // given
        let leaf = Fixtures.snapshot(hasContents: true)
        let container2 = Fixtures.snapshot(children: [leaf])
        let container1 = Fixtures.snapshot(children: [container2])
        let root = Fixtures.snapshot(children: [container1])

        // when
        let result = root.removingInvisible()

        // then
        #expect(result?.children.count == 1)
        #expect(result?.children[0].children.count == 1)
        #expect(result?.children[0].children[0].children.count == 1)
    }
}
#endif
