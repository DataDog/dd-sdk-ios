/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import Testing

@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshotTests.Fixtures {
    static let rootBounds = CGRect(x: 0, y: 0, width: 200, height: 300)

    static func rootLayer() -> CALayer {
        let root = CALayer()
        root.bounds = rootBounds
        return root
    }

    static func changeset(
        for layer: CALayer,
        aspects: CALayerChange.Aspect.Set
    ) -> CALayerChangeset {
        CALayerChangeset([
            ObjectIdentifier(layer): .init(
                layer: .init(layer),
                aspects: aspects
            )
        ])
    }
}

extension LayerSnapshotTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func throwsMissingLayerWhenSnapshotReferenceIsDeallocated() {
        // given
        let rootLayer = Fixtures.rootLayer()

        let snapshot: LayerSnapshot = {
            var layer: CALayer? = CALayer()
            let snapshot = Fixtures.snapshot(
                layer: layer!,
                frame: CGRect(x: 0, y: 0, width: 50, height: 50),
                clipRect: Fixtures.rootBounds
            )
            layer = nil
            return snapshot
        }()

        // when / then
        #expect(throws: LayerImageChangeError.missingLayer) {
            _ = try snapshot.layerImageChange(
                with: CALayerChangeset(),
                imageRects: [:],
                relativeTo: rootLayer
            )
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func throwsInvalidRectWhenVisibleRectIsEmpty() {
        // given
        let rootLayer = Fixtures.rootLayer()
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 50, height: 50)
        rootLayer.addSublayer(layer)

        let snapshot = Fixtures.snapshot(
            layer: layer,
            frame: CGRect(x: 300, y: 300, width: 50, height: 50),
            clipRect: Fixtures.rootBounds
        )

        // when / then
        #expect(throws: LayerImageChangeError.invalidRect) {
            _ = try snapshot.layerImageChange(
                with: CALayerChangeset(),
                imageRects: [:],
                relativeTo: rootLayer
            )
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func plainLayerWithoutContentsOrChangesDoesNotNeedRenderOnFirstAppearance() throws {
        // given
        let rootLayer = Fixtures.rootLayer()
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let snapshot = Fixtures.snapshot(
            layer: layer,
            replayID: 10,
            frame: layer.convert(layer.bounds, to: rootLayer),
            clipRect: Fixtures.rootBounds,
            hasContents: false
        )

        // when
        let change = try snapshot.layerImageChange(
            with: CALayerChangeset(),
            imageRects: [:],
            relativeTo: rootLayer
        )

        // then
        #expect(change.needsRender == false)
        #expect(change.rect.equalTo(layer.bounds))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func plainLayerWithContentsNeedsRenderOnFirstAppearance() throws {
        // given
        let rootLayer = Fixtures.rootLayer()
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let snapshot = Fixtures.snapshot(
            layer: layer,
            replayID: 11,
            frame: layer.convert(layer.bounds, to: rootLayer),
            clipRect: Fixtures.rootBounds,
            hasContents: true
        )

        // when
        let change = try snapshot.layerImageChange(
            with: CALayerChangeset(),
            imageRects: [:],
            relativeTo: rootLayer
        )

        // then
        #expect(change.needsRender)
        #expect(change.rect.equalTo(layer.bounds))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func layerSubclassWithoutChangesDoesNotNeedRenderAfterFirstAppearance() throws {
        // given
        let rootLayer = Fixtures.rootLayer()
        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let snapshot = Fixtures.snapshot(
            layer: layer,
            replayID: 12,
            frame: layer.convert(layer.bounds, to: rootLayer),
            clipRect: Fixtures.rootBounds
        )

        // when
        let change = try snapshot.layerImageChange(
            with: CALayerChangeset(),
            imageRects: [snapshot.replayID: layer.bounds],
            relativeTo: rootLayer
        )

        // then
        #expect(change.needsRender == false)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func layerSubclassWithDisplayChangeNeedsRender() throws {
        // given
        let rootLayer = Fixtures.rootLayer()
        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let snapshot = Fixtures.snapshot(
            layer: layer,
            replayID: 13,
            frame: layer.convert(layer.bounds, to: rootLayer),
            clipRect: Fixtures.rootBounds
        )
        let changes = Fixtures.changeset(for: layer, aspects: [.display])

        // when
        let change = try snapshot.layerImageChange(
            with: changes,
            imageRects: [snapshot.replayID: layer.bounds],
            relativeTo: rootLayer
        )

        // then
        #expect(change.needsRender)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func partialImageNeedsRenderWhenVisibleRectLeavesCachedRect() throws {
        // given
        let rootLayer = Fixtures.rootLayer()
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 400, height: 120)
        layer.position = CGPoint(x: 200, y: 60)
        rootLayer.addSublayer(layer)

        let snapshot = Fixtures.snapshot(
            layer: layer,
            replayID: 14,
            frame: layer.convert(layer.bounds, to: rootLayer),
            clipRect: CGRect(x: 180, y: 0, width: 20, height: 120),
            hasContents: false
        )

        let previousPartialRect = CGRect(x: 0, y: 0, width: 10, height: 120)

        // when
        let change = try snapshot.layerImageChange(
            with: CALayerChangeset(),
            imageRects: [snapshot.replayID: previousPartialRect],
            relativeTo: rootLayer
        )

        // then
        #expect(change.needsRender)
        #expect(change.rect.origin.x == 180)
        #expect(change.rect.size == CGSize(width: 20, height: 120))
    }
}
#endif
