/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import QuartzCore
import TestUtilities
import Testing
import UIKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct CALayerSnapshotTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures layer identity and visual properties")
    func capturesLayerIdentityAndVisualProperties() throws {
        try CALayer.withReplayIDGenerator(ReplayIDGenerator { 42 }) {
            // Given
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            let layer = view.layer
            let contents = NSObject()
            let mask = CALayer()
            let shadowPath = CGPath(rect: CGRect(x: 0, y: 0, width: 40, height: 40), transform: nil)

            layer.contents = contents
            layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
            layer.position = CGPoint(x: 20, y: 30)
            layer.zPosition = 7
            layer.transform = CATransform3DMakeScale(2, 3, 1)
            layer.sublayerTransform.m34 = -1 / 500
            layer.mask = mask
            layer.masksToBounds = true
            layer.isOpaque = true
            layer.backgroundColor = UIColor.red.cgColor
            layer.cornerCurve = .continuous
            layer.borderWidth = 2
            layer.borderColor = UIColor.green.cgColor
            layer.opacity = 0.5
            layer.allowsGroupOpacity = false
            layer.shadowColor = UIColor.blue.cgColor
            layer.shadowOpacity = 0.25
            layer.shadowOffset = CGSize(width: 3, height: 4)
            layer.shadowRadius = 5
            layer.shadowPath = shadowPath

            // When
            let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

            // Then
            #expect(snapshot.layer.matches(layer))
            #expect(snapshot.replayID == 42)
            #expect(snapshot.layerClass == type(of: layer))
            #expect(snapshot.delegateClass == UIView.self)
            #expect(snapshot.contentsClass == NSObject.self)
            #expect(snapshot.bounds == layer.bounds)
            #expect(snapshot.position == layer.position)
            #expect(snapshot.zPosition == layer.zPosition)
            #expect(snapshot.transform.m11 == 2)
            #expect(snapshot.transform.m22 == 3)
            #expect(snapshot.sublayerTransform.m34 == CGFloat(-1) / 500)
            #expect(snapshot.mask?.layer.matches(mask) == true)
            #expect(snapshot.masksToBounds)
            #expect(snapshot.isOpaque)
            #expect(snapshot.backgroundColor == UIColor.red.cgColor)
            #expect(snapshot.cornerCurve == .continuous)
            #expect(snapshot.borderWidth == 2)
            #expect(snapshot.borderColor == UIColor.green.cgColor)
            #expect(snapshot.opacity == 0.5)
            #expect(!snapshot.allowsGroupOpacity)
            #expect(snapshot.shadowColor == UIColor.blue.cgColor)
            #expect(snapshot.shadowOpacity == 0.25)
            #expect(snapshot.shadowOffset == CGSize(width: 3, height: 4))
            #expect(snapshot.shadowRadius == 5)
            #expect(snapshot.shadowPath == shadowPath)
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Preserves sublayer order")
    func preservesSublayerOrder() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let backLayer = CALayer()
        backLayer.frame = CGRect(x: 0, y: 0, width: 10, height: 10)

        let middleLayer = CALayer()
        middleLayer.frame = CGRect(x: 10, y: 0, width: 10, height: 10)

        let frontLayer = CALayer()
        frontLayer.frame = CGRect(x: 20, y: 0, width: 10, height: 10)

        root.addSublayer(backLayer)
        root.addSublayer(middleLayer)
        root.addSublayer(frontLayer)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        let capturedLayers = snapshot.sublayers.map(\.layer)

        #expect(snapshot.sublayers.count == 3)
        #expect(capturedLayers.elementsEqual([backLayer, middleLayer, frontLayer]) { $0.matches($1) })
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures nested hierarchy with absolute frames")
    func capturesNestedHierarchyWithAbsoluteFrames() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let parent = CALayer()
        parent.frame = CGRect(x: 20, y: 30, width: 100, height: 100)
        root.addSublayer(parent)

        let child = CALayer()
        child.frame = CGRect(x: 10, y: 15, width: 20, height: 25)
        parent.addSublayer(child)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        let parentSnapshot = try #require(snapshot.sublayers.first)
        let childSnapshot = try #require(parentSnapshot.sublayers.first)

        #expect(snapshot.absoluteFrame == CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(parentSnapshot.absoluteFrame == CGRect(x: 20, y: 30, width: 100, height: 100))
        #expect(childSnapshot.absoluteFrame == CGRect(x: 30, y: 45, width: 20, height: 25))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Prunes hidden and transparent layer trees")
    func prunesHiddenAndTransparentLayerTrees() throws {
        // Given
        let hiddenRoot = CALayer()
        hiddenRoot.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        hiddenRoot.isHidden = true

        let transparentRoot = CALayer()
        transparentRoot.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        transparentRoot.opacity = 0

        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let visibleChild = CALayer()
        visibleChild.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        root.addSublayer(visibleChild)

        let hiddenChild = CALayer()
        hiddenChild.frame = CGRect(x: 10, y: 0, width: 10, height: 10)
        hiddenChild.isHidden = true
        hiddenChild.addSublayer(CALayer())
        root.addSublayer(hiddenChild)

        let transparentChild = CALayer()
        transparentChild.frame = CGRect(x: 20, y: 0, width: 10, height: 10)
        transparentChild.opacity = 0
        transparentChild.addSublayer(CALayer())
        root.addSublayer(transparentChild)

        // When
        let hiddenRootSnapshot = CALayerSnapshot(from: hiddenRoot, in: .mockAny())
        let transparentRootSnapshot = CALayerSnapshot(from: transparentRoot, in: .mockAny())
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        #expect(hiddenRootSnapshot == nil)
        #expect(transparentRootSnapshot == nil)
        #expect(snapshot.sublayers.count == 1)
        #expect(snapshot.sublayers.first?.layer.matches(visibleChild) == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Prunes layer trees outside visible bounds")
    func prunesLayerTreesOutsideVisibleBounds() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let visibleChild = CALayer()
        visibleChild.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        root.addSublayer(visibleChild)

        let outsideChild = CALayer()
        outsideChild.frame = CGRect(x: 120, y: 10, width: 20, height: 20)
        outsideChild.addSublayer(CALayer())
        root.addSublayer(outsideChild)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        #expect(snapshot.sublayers.count == 1)
        #expect(snapshot.sublayers.first?.layer.matches(visibleChild) == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Prunes sublayers outside clipping parent bounds")
    func prunesSublayersOutsideClippingParentBounds() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let parent = CALayer()
        parent.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        parent.masksToBounds = true
        root.addSublayer(parent)

        let child = CALayer()
        child.frame = CGRect(x: 60, y: 0, width: 20, height: 20)
        parent.addSublayer(child)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        let parentSnapshot = try #require(snapshot.sublayers.first)
        #expect(parentSnapshot.sublayers.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Prunes sublayers outside nested clipping bounds")
    func prunesSublayersOutsideNestedClippingBounds() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 300, height: 300)

        let outer = CALayer()
        outer.frame = CGRect(x: 50, y: 50, width: 200, height: 200)
        outer.masksToBounds = true
        root.addSublayer(outer)

        let inner = CALayer()
        inner.frame = CGRect(x: 150, y: 0, width: 100, height: 100)
        inner.masksToBounds = true
        outer.addSublayer(inner)

        let visibleChild = CALayer()
        visibleChild.frame = CGRect(x: 10, y: 10, width: 30, height: 30)
        inner.addSublayer(visibleChild)

        let clippedChild = CALayer()
        clippedChild.frame = CGRect(x: 60, y: 10, width: 30, height: 30)
        inner.addSublayer(clippedChild)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        let outerSnapshot = try #require(snapshot.sublayers.first)
        let innerSnapshot = try #require(outerSnapshot.sublayers.first)

        #expect(innerSnapshot.sublayers.count == 1)
        #expect(innerSnapshot.sublayers.first?.layer.matches(visibleChild) == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Prunes empty clipping layer trees")
    func prunesEmptyClippingLayerTrees() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let emptyLayer = CALayer()
        emptyLayer.frame = CGRect(x: 10, y: 10, width: 0, height: 20)
        emptyLayer.masksToBounds = true
        root.addSublayer(emptyLayer)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        #expect(snapshot.sublayers.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Applies hide privacy override and ignores private subtree")
    func appliesHidePrivacyOverrideAndIgnoresPrivateSubtree() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let privateView = UIView(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
        privateView.dd.sessionReplayPrivacyOverrides.hide = true
        root.addSublayer(privateView.layer)

        let child = CALayer()
        child.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        privateView.layer.addSublayer(child)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))

        // Then
        let privateSnapshot = try #require(snapshot.sublayers.first)
        #expect(privateSnapshot.isPrivate)
        #expect(privateSnapshot.observation.semantics == .layer)
        #expect(privateSnapshot.sublayers.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Propagates privacy overrides to descendants")
    func propagatesPrivacyOverridesToDescendants() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let parentView = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        parentView.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = .maskAllInputs
        parentView.dd.sessionReplayPrivacyOverrides.imagePrivacy = .maskNone
        root.addSublayer(parentView.layer)

        let childView = UIView(frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        childView.dd.sessionReplayPrivacyOverrides.imagePrivacy = .maskNonBundledOnly
        parentView.layer.addSublayer(childView.layer)

        let context = CALayerSnapshot.Context.mockAny(
            textAndInputPrivacyLevel: .maskSensitiveInputs,
            imagePrivacyLevel: .maskAll
        )

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: context))

        // Then
        let parentSnapshot = try #require(snapshot.sublayers.first)
        let childSnapshot = try #require(parentSnapshot.sublayers.first)

        #expect(snapshot.textAndInputPrivacyLevel == .maskSensitiveInputs)
        #expect(snapshot.imagePrivacyLevel == .maskAll)
        #expect(parentSnapshot.textAndInputPrivacyLevel == .maskAllInputs)
        #expect(parentSnapshot.imagePrivacyLevel == .maskNone)
        #expect(childSnapshot.textAndInputPrivacyLevel == .maskAllInputs)
        #expect(childSnapshot.imagePrivacyLevel == .maskNonBundledOnly)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures content geometry")
    func capturesContentGeometry() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let layer = CALayer()
        layer.frame = CGRect(x: 20, y: 30, width: 80, height: 40)
        root.addSublayer(layer)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let layerSnapshot = try #require(snapshot.sublayers.first)

        // Then
        #expect(layerSnapshot.contentGeometry.renderBounds == layer.bounds)
        #expect(layerSnapshot.contentGeometry.localRect == layer.bounds)
        #expect(layerSnapshot.contentGeometry.frame == layer.frame)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Expands content geometry to include ignored sublayers")
    func expandsContentGeometryToIncludeIgnoredSublayers() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let imageView = UIImageView(frame: CGRect(x: 50, y: 60, width: 30, height: 30))
        root.addSublayer(imageView.layer)

        let ignoredSublayer = CALayer()
        ignoredSublayer.frame = CGRect(x: -10, y: -12, width: 50, height: 54)
        imageView.layer.addSublayer(ignoredSublayer)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let imageSnapshot = try #require(snapshot.sublayers.first)

        // Then
        #expect(imageSnapshot.contentGeometry.renderBounds == ignoredSublayer.frame)
        #expect(imageSnapshot.contentGeometry.localRect == ignoredSublayer.frame)
        #expect(imageSnapshot.contentGeometry.frame == CGRect(x: 40, y: 48, width: 50, height: 54))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Keeps content geometry within an ignored subtree owner that clips")
    func keepsContentGeometryWithinIgnoredSublayerOwnerThatClips() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let imageView = UIImageView(frame: CGRect(x: 50, y: 60, width: 30, height: 30))
        imageView.layer.masksToBounds = true
        root.addSublayer(imageView.layer)

        let ignoredSublayer = CALayer()
        ignoredSublayer.frame = CGRect(x: -10, y: -12, width: 50, height: 54)
        imageView.layer.addSublayer(ignoredSublayer)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let imageSnapshot = try #require(snapshot.sublayers.first)

        // Then
        #expect(imageSnapshot.contentGeometry.renderBounds == imageView.layer.bounds)
        #expect(imageSnapshot.contentGeometry.localRect == imageView.layer.bounds)
        #expect(imageSnapshot.contentGeometry.frame == imageView.layer.frame)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures complete geometry for a non-oversized layer clipped by an ancestor")
    func capturesCompleteGeometryForNonOversizedLayerClippedByAncestor() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let parent = CALayer()
        parent.frame = CGRect(x: 20, y: 30, width: 50, height: 50)
        parent.masksToBounds = true
        root.addSublayer(parent)

        let child = CATextLayer()
        child.frame = CGRect(x: 30, y: 10, width: 40, height: 20)
        parent.addSublayer(child)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let parentSnapshot = try #require(snapshot.sublayers.first)
        let childSnapshot = try #require(parentSnapshot.sublayers.first)

        // Then
        #expect(childSnapshot.contentGeometry.renderBounds == child.bounds)
        #expect(childSnapshot.contentGeometry.localRect == child.bounds)
        #expect(childSnapshot.contentGeometry.frame == child.convert(child.bounds, to: root))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Crops oversized content geometry to the viewport")
    func cropsOversizedContentGeometryToViewport() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let oversizedLayer = CALayer()
        oversizedLayer.frame = CGRect(x: -180, y: 0, width: 400, height: 120)
        root.addSublayer(oversizedLayer)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let oversizedSnapshot = try #require(snapshot.sublayers.first)

        // Then
        #expect(oversizedSnapshot.contentGeometry.renderBounds == oversizedLayer.bounds)
        #expect(oversizedSnapshot.contentGeometry.localRect == CGRect(x: 180, y: 0, width: 100, height: 100))
        #expect(oversizedSnapshot.contentGeometry.frame == root.bounds)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures per-corner radii")
    func capturesPerCornerRadii() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.cornerRadius = 8

        let cornerRadii = CALayerSnapshot.CornerRadii(
            topLeft: CGSize(width: 1, height: 2),
            topRight: CGSize(width: 3, height: 4),
            bottomLeft: CGSize(width: 5, height: 6),
            bottomRight: CGSize(width: 7, height: 8)
        )
        layer.setValue(cornerRadii.nsValue, forKey: "cornerRadii")

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(snapshot.cornerRadii == cornerRadii)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures masked corner radii")
    func capturesMaskedCornerRadii() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.cornerRadius = 8
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMaxYCorner]

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(snapshot.cornerRadii.topLeft == CGSize(width: 8, height: 8))
        #expect(snapshot.cornerRadii.topRight == .zero)
        #expect(snapshot.cornerRadii.bottomLeft == .zero)
        #expect(snapshot.cornerRadii.bottomRight == CGSize(width: 8, height: 8))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Ignores non-finite corner radius")
    func ignoresNonFiniteCornerRadius() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 37, height: 24)
        layer.cornerRadius = .nan

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(snapshot.cornerRadii == .zero)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension CALayerSnapshot.CornerRadii {
    var nsValue: NSValue {
        var value = self
        return withUnsafePointer(to: &value) {
            NSValue(bytes: $0, objCType: "{CACornerRadii={CGSize=dd}{CGSize=dd}{CGSize=dd}{CGSize=dd}}")
        }
    }
}

#endif
