/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Testing
import QuartzCore
import UIKit
import WebKit

@testable import DatadogSessionReplay

@MainActor
struct LayerSnapshotTests {
    @available(iOS 13.0, tvOS 13.0, *)
    enum Fixtures {
        static var anyImage: CGImage {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            return context.makeImage()!
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func snapshotSingleLayer() {
        CALayer.withReplayIDGenerator(.autoincrementing) {
            // given
            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)

            // when
            let snapshot = LayerSnapshot(from: layer, in: .mockAny())

            // then
            #expect(snapshot.replayID == 0)
            #expect(snapshot.children.isEmpty)
            #expect(snapshot.path == "CALayer#0")
            #expect(snapshot.isSnapshot(of: layer))
            #expect(snapshot.semantics == .generic)
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func capturesWKWebViewSemantics() {
        // given
        let webView = WKWebView()
        webView.layer.addSublayer(CALayer())

        // when
        let snapshot = LayerSnapshot(from: webView.layer, in: .mockAny())

        // then
        #expect(snapshot.semantics == .webView(slotID: webView.hash))
        #expect(snapshot.children.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func snapshotNestedHierarchy() {
        CALayer.withReplayIDGenerator(.autoincrementing) {
            // given
            let root = CALayer()
            let child = CALayer()
            let grandchild = CALayer()
            root.addSublayer(child)
            child.addSublayer(grandchild)

            // when
            let snapshot = LayerSnapshot(from: root, in: .mockAny())

            // then
            #expect(snapshot.replayID == 2)
            #expect(snapshot.children.count == 1)
            #expect(snapshot.children[0].replayID == 1)
            #expect(snapshot.children[0].children.count == 1)
            #expect(snapshot.children[0].children[0].replayID == 0)
            #expect(snapshot.children[0].children[0].children.isEmpty)
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func preservesZOrder() {
        // given
        let parent = CALayer()
        let backLayer = CALayer()
        let middleLayer = CALayer()
        let frontLayer = CALayer()

        parent.addSublayer(backLayer)
        parent.addSublayer(middleLayer)
        parent.addSublayer(frontLayer)

        // when
        let snapshot = LayerSnapshot(from: parent, in: .mockAny())

        // then
        #expect(snapshot.children.count == 3)
        #expect(snapshot.children[0].isSnapshot(of: backLayer))
        #expect(snapshot.children[1].isSnapshot(of: middleLayer))
        #expect(snapshot.children[2].isSnapshot(of: frontLayer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func sameTypeSiblingsHaveIncrementingIndices() {
        // given
        let parent = CALayer()
        let child1 = CALayer()
        let child2 = CALayer()
        let child3 = CALayer()
        parent.addSublayer(child1)
        parent.addSublayer(child2)
        parent.addSublayer(child3)

        // when
        let snapshot = LayerSnapshot(from: parent, in: .mockAny())

        // then
        #expect(snapshot.children[0].path == "CALayer#0/CALayer#0")
        #expect(snapshot.children[1].path == "CALayer#0/CALayer#1")
        #expect(snapshot.children[2].path == "CALayer#0/CALayer#2")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func differentTypeSiblingsHaveSeparateIndices() {
        // given
        let parent = CALayer()
        let regularLayer = CALayer()
        let shapeLayer = CAShapeLayer()
        let anotherRegularLayer = CALayer()
        parent.addSublayer(regularLayer)
        parent.addSublayer(shapeLayer)
        parent.addSublayer(anotherRegularLayer)

        // when
        let snapshot = LayerSnapshot(from: parent, in: .mockAny())

        // then
        #expect(snapshot.children[0].path == "CALayer#0/CALayer#0")
        #expect(snapshot.children[1].path == "CALayer#0/CAShapeLayer#0")
        #expect(snapshot.children[2].path == "CALayer#0/CALayer#1")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func fortyFiveDegreesRotatedLayerIsNotAxisAligned() {
        // given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: .pi / 4))

        // when
        let snapshot = LayerSnapshot(from: layer, in: .mockAny())

        // then
        #expect(!snapshot.isAxisAligned)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func ninetyDegreesRotatedLayerIsAxisAligned() {
        // given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: .pi / 2))

        // when
        let snapshot = LayerSnapshot(from: layer, in: .mockAny())

        // then
        #expect(snapshot.isAxisAligned)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func layerWithIdentityTransformIsAxisAligned() {
        // given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        // when
        let snapshot = LayerSnapshot(from: layer, in: .mockAny())

        // then
        #expect(snapshot.isAxisAligned)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func nonAffinePerspectiveTransformIsNotAxisAligned() {
        // given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 500
        layer.transform = CATransform3DRotate(transform, .pi / 4, 0, 1, 0)

        // when
        let snapshot = LayerSnapshot(from: layer, in: .mockAny())

        // then
        #expect(!snapshot.isAxisAligned)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func capturesVisualProperties() {
        // given
        let layer = CALayer()
        layer.opacity = 0.5
        layer.isHidden = true
        layer.backgroundColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)

        // when
        let snapshot = LayerSnapshot(from: layer, in: .mockAny())

        // then
        #expect(snapshot.opacity == 0.5)
        #expect(snapshot.resolvedOpacity == 0.5)
        #expect(snapshot.isHidden == true)
        #expect(snapshot.backgroundColor != nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func resolvesNestedOpacity() {
        // given
        let rootLayer = CALayer()
        rootLayer.opacity = 0.5

        let childLayer = CALayer()
        childLayer.opacity = 0.5
        rootLayer.addSublayer(childLayer)

        // when
        let snapshot = LayerSnapshot(from: rootLayer, in: .mockAny())

        // then
        #expect(snapshot.resolvedOpacity == 0.5)
        #expect(snapshot.children[0].resolvedOpacity == 0.25)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func propagatesAncestorMaskToDescendants() {
        // given
        let rootLayer = CALayer()
        rootLayer.mask = CALayer()

        let childLayer = CALayer()
        rootLayer.addSublayer(childLayer)

        // when
        let snapshot = LayerSnapshot(from: rootLayer, in: .mockAny())

        // then
        #expect(snapshot.hasMask)
        #expect(snapshot.children[0].hasMask)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func capturesShapeProperties() {
        // given
        let layer = CALayer()
        layer.cornerRadius = 10
        layer.borderWidth = 2
        layer.borderColor = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        layer.masksToBounds = true

        // when
        let snapshot = LayerSnapshot(from: layer, in: .mockAny())

        // then
        #expect(snapshot.cornerRadius == 10)
        #expect(snapshot.borderWidth == 2)
        #expect(snapshot.borderColor != nil)
        #expect(snapshot.masksToBounds == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func capturesHasContents() {
        // given
        let layer = CALayer()
        let layerWithContents = CALayer()
        layerWithContents.contents = Fixtures.anyImage

        // when
        let snapshot = LayerSnapshot(from: layer, in: .mockAny())
        let snapshotWithContents = LayerSnapshot(from: layerWithContents, in: .mockAny())

        // then
        #expect(snapshotWithContents.hasContents)
        #expect(!snapshot.hasContents)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func capturesZPosition() {
        // given
        let layer = CALayer()
        layer.zPosition = 42.0

        // when
        let snapshot = LayerSnapshot(from: layer, in: .mockAny())

        // then
        #expect(snapshot.zPosition == 42.0)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func capturesFrame() {
        // given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        rootLayer.position = CGPoint(x: 200, y: 150)

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        layer.position = CGPoint(x: 50, y: 50)
        rootLayer.addSublayer(layer)

        // when
        let snapshot = LayerSnapshot(from: rootLayer, in: .mockAny())

        // then
        #expect(snapshot.frame == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(snapshot.children[0].frame == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func capturesClipRect() {
        // given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        rootLayer.masksToBounds = false

        let clippingLayer = CALayer()
        clippingLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 150)
        clippingLayer.position = CGPoint(x: 100, y: 75)
        clippingLayer.masksToBounds = true
        rootLayer.addSublayer(clippingLayer)

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        layer.position = CGPoint(x: 50, y: 25)
        clippingLayer.addSublayer(layer)

        // when
        let snapshot = LayerSnapshot(from: rootLayer, in: .mockAny())

        // then
        let rootBounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        #expect(snapshot.clipRect == rootBounds)
        #expect(snapshot.children[0].clipRect == rootBounds)
        #expect(snapshot.children[0].children[0].clipRect == CGRect(x: 0, y: 0, width: 200, height: 150))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func accumulatesNestedClipRects() {
        // given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 400, height: 400)

        let outerLayer = CALayer()
        outerLayer.bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
        outerLayer.position = CGPoint(x: 150, y: 150)
        outerLayer.masksToBounds = true
        rootLayer.addSublayer(outerLayer)

        let innerLayer = CALayer()
        innerLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        innerLayer.position = CGPoint(x: 150, y: 150)
        innerLayer.masksToBounds = true
        outerLayer.addSublayer(innerLayer)

        let leafLayer = CALayer()
        leafLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        leafLayer.position = CGPoint(x: 50, y: 50)
        innerLayer.addSublayer(leafLayer)

        // when
        let snapshot = LayerSnapshot(from: rootLayer, in: .mockAny())
        let outerSnapshot = snapshot.children[0]
        let innerSnapshot = outerSnapshot.children[0]
        let leafSnapshot = innerSnapshot.children[0]

        // then
        #expect(snapshot.clipRect == CGRect(x: 0, y: 0, width: 400, height: 400))
        #expect(outerSnapshot.clipRect == CGRect(x: 0, y: 0, width: 400, height: 400))
        #expect(innerSnapshot.clipRect == CGRect(x: 0, y: 0, width: 300, height: 300))
        #expect(leafSnapshot.clipRect == CGRect(x: 50, y: 50, width: 200, height: 200))
    }
}
#endif
