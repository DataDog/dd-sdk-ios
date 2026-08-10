/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
import QuartzCore
import TestUtilities
import Testing
import UIKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct CALayerSnapshotOcclusionTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Draws content when the contents property is set")
    func drawsContentWhenContentsPropertyIsSet() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.contents = NSObject()

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(snapshot.drawsContent)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Draws content when the layer has a visible background color")
    func drawsContentWhenLayerHasAVisibleBackgroundColor() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.backgroundColor = UIColor.red.cgColor

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(snapshot.drawsContent)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Draws content when the layer has a visible border")
    func drawsContentWhenLayerHasAVisibleBorder() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.borderWidth = 1
        layer.borderColor = UIColor.black.cgColor

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(snapshot.drawsContent)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not draw content when the layer is bare")
    func doesNotDrawContentWhenLayerIsBare() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(!snapshot.drawsContent)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Draws content when the layer subclass has unmodeled drawing state")
    func drawsContentWhenLayerSubclassHasUnmodeledDrawingState() throws {
        // Given
        let layer = CAShapeLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.path = UIBezierPath(rect: layer.bounds).cgPath
        layer.fillColor = UIColor.red.cgColor

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(snapshot.drawsContent)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is an occluder when fully opaque with a solid background")
    func isOccluderWhenFullyOpaqueWithSolidBackground() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.backgroundColor = UIColor.red.cgColor

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(snapshot.isOccluder)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is not an occluder when opacity is less than one")
    func isNotOccluderWhenOpacityIsLessThanOne() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.backgroundColor = UIColor.red.cgColor
        layer.opacity = 0.5

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(!snapshot.isOccluder)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is not an occluder when the background is translucent")
    func isNotOccluderWhenBackgroundIsTranslucent() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.backgroundColor = UIColor.red.withAlphaComponent(0.5).cgColor

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(!snapshot.isOccluder)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is not an occluder when a mask is present")
    func isNotOccluderWhenMaskIsPresent() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.backgroundColor = UIColor.red.cgColor
        layer.mask = CALayer()

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(!snapshot.isOccluder)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is not an occluder when rotated")
    func isNotOccluderWhenRotated() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.backgroundColor = UIColor.red.cgColor
        layer.transform = CATransform3DMakeRotation(.pi / 8, 0, 0, 1)

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(!snapshot.isOccluder)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is not an occluder when a filter affects opacity")
    func isNotOccluderWhenFilterAffectsOpacity() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.backgroundColor = UIColor.red.cgColor
        layer.filters = [try NSObject.makeCAFilter(type: "glassBackground")]

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(!snapshot.isOccluder)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is not an occluder when a compositing filter is applied")
    func isNotOccluderWhenCompositingFilterIsApplied() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.backgroundColor = UIColor.red.cgColor
        layer.compositingFilter = "plusD"

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(!snapshot.isOccluder)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is an occluder when filters preserve opacity")
    func isOccluderWhenFiltersPreserveOpacity() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.backgroundColor = UIColor.red.cgColor
        layer.filters = [try NSObject.makeCAFilter(type: "gaussianBlur")]

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(snapshot.isOccluder)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Returns the visible frame as the only occlusion rect when corners are not rounded")
    func returnsVisibleFrameAsOnlyOcclusionRectWhenCornersAreNotRounded() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 40, height: 60)

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let rects = snapshot.occlusionRects(in: CGRect(x: 0, y: 0, width: 40, height: 60))

        // Then
        #expect(rects == [CGRect(x: 0, y: 0, width: 40, height: 60)])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Insets each edge by the larger of the two adjacent corner radii")
    func insetsEachEdgeByTheLargerOfTheTwoAdjacentCornerRadii() {
        // Given
        let radii = CALayerSnapshot.CornerRadii(
            topLeft: CGSize(width: 4, height: 4),
            topRight: CGSize(width: 12, height: 12),
            bottomLeft: .zero,
            bottomRight: CGSize(width: 8, height: 8)
        )

        // When
        let rects = radii.occlusionRects(in: CGRect(x: 0, y: 0, width: 100, height: 100))

        // Then
        #expect(rects.contains(CGRect(x: 0, y: 12, width: 100, height: 80)))
        #expect(rects.contains(CGRect(x: 4, y: 0, width: 84, height: 100)))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Drops a band whose inset exceeds the available extent")
    func dropsBandWhoseInsetExceedsAvailableExtent() {
        // Given
        let radii = CALayerSnapshot.CornerRadii(
            topLeft: CGSize(width: 12, height: 12),
            topRight: CGSize(width: 12, height: 12),
            bottomLeft: CGSize(width: 12, height: 12),
            bottomRight: CGSize(width: 12, height: 12)
        )

        // When
        let rects = radii.occlusionRects(in: CGRect(x: 0, y: 0, width: 40, height: 20))

        // Then
        #expect(rects == [CGRect(x: 12, y: 0, width: 16, height: 20)])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes a content-bearing leaf fully covered by an opaque sibling in front")
    func removesLeafFullyCoveredByOpaqueSiblingInFront() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let behind = CALayer()
        behind.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        behind.backgroundColor = UIColor.green.cgColor
        behind.zPosition = 0
        root.addSublayer(behind)

        let front = CALayer()
        front.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        front.backgroundColor = UIColor.red.cgColor
        front.zPosition = 1
        root.addSublayer(front)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(result.sublayers.map(\.absoluteFrame) == [CGRect(x: 0, y: 0, width: 100, height: 100)])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Keeps a content-bearing leaf that is only partially covered")
    func keepsLeafPartiallyCoveredByOpaqueSibling() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let behind = CALayer()
        behind.frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        behind.backgroundColor = UIColor.green.cgColor
        behind.zPosition = 0
        root.addSublayer(behind)

        let front = CALayer()
        front.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        front.backgroundColor = UIColor.red.cgColor
        front.zPosition = 1
        root.addSublayer(front)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(
            result.sublayers.map(\.absoluteFrame) == [
                CGRect(x: 0, y: 0, width: 60, height: 60),
                CGRect(x: 0, y: 0, width: 40, height: 40)
            ]
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Keeps a layer subclass with unmodeled drawing state")
    func keepsLayerSubclassWithUnmodeledDrawingState() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let shape = CAShapeLayer()
        shape.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        shape.path = UIBezierPath(rect: shape.bounds).cgPath
        shape.fillColor = UIColor.red.cgColor
        root.addSublayer(shape)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(result.sublayers.map(\.absoluteFrame) == [CGRect(x: 10, y: 10, width: 20, height: 20)])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Keeps a covered content-bearing leaf when it casts a shadow")
    func keepsCoveredContentBearingLeafWhenItCastsShadow() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let behindColor = UIColor.green.cgColor
        let behind = CALayer()
        behind.frame = CGRect(x: 16, y: 16, width: 32, height: 32)
        behind.backgroundColor = behindColor
        behind.shadowColor = UIColor.black.cgColor
        behind.shadowOpacity = 1
        behind.zPosition = 0
        root.addSublayer(behind)

        let frontColor = UIColor.red.cgColor
        let front = CALayer()
        front.frame = CGRect(x: 16, y: 16, width: 32, height: 32)
        front.backgroundColor = frontColor
        front.zPosition = 1
        root.addSublayer(front)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(result.sublayers.map(\.backgroundColor) == [behindColor, frontColor])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes a covered content-bearing container once its children are removed")
    func removesCoveredContentBearingContainerOnceChildrenAreRemoved() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let container = CALayer()
        container.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        container.backgroundColor = UIColor.green.cgColor
        container.zPosition = 0
        let containerChild = CALayer()
        containerChild.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        containerChild.backgroundColor = UIColor.blue.cgColor
        container.addSublayer(containerChild)
        root.addSublayer(container)

        let front = CALayer()
        front.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        front.backgroundColor = UIColor.red.cgColor
        front.zPosition = 1
        root.addSublayer(front)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(result.sublayers.map(\.absoluteFrame) == [CGRect(x: 0, y: 0, width: 100, height: 100)])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not propagate opaque coverage past a masksToBounds ancestor")
    func doesNotPropagateCoveragePastMasksToBoundsAncestor() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let clipper = CALayer()
        clipper.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        clipper.masksToBounds = true
        clipper.zPosition = 0

        let opaqueChild = CALayer()
        opaqueChild.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        opaqueChild.backgroundColor = UIColor.red.cgColor
        clipper.addSublayer(opaqueChild)
        root.addSublayer(clipper)

        let behind = CALayer()
        behind.frame = CGRect(x: 120, y: 120, width: 40, height: 40)
        behind.backgroundColor = UIColor.green.cgColor
        behind.zPosition = -1
        root.addSublayer(behind)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(
            result.sublayers.map(\.absoluteFrame) == [
                CGRect(x: 120, y: 120, width: 40, height: 40),
                CGRect(x: 0, y: 0, width: 100, height: 100),
            ]
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not treat a descendant of a semi-transparent ancestor as an occluder")
    func doesNotTreatDescendantOfSemiTransparentAncestorAsOccluder() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let parent = CALayer()
        parent.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        parent.opacity = 0.5
        parent.zPosition = 1

        let child = CALayer()
        child.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        child.backgroundColor = UIColor.red.cgColor
        parent.addSublayer(child)
        root.addSublayer(parent)

        let behind = CALayer()
        behind.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        behind.backgroundColor = UIColor.green.cgColor
        behind.zPosition = 0
        root.addSublayer(behind)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(
            result.sublayers.map(\.absoluteFrame) == [
                CGRect(x: 0, y: 0, width: 20, height: 20),
                CGRect(x: 0, y: 0, width: 100, height: 100),
            ]
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes an empty structural container when all its children are removed")
    func removesEmptyStructuralContainerWhenAllChildrenRemoved() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let container = CALayer()
        container.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        container.zPosition = 0

        let containerChild = CALayer()
        containerChild.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        containerChild.backgroundColor = UIColor.blue.cgColor
        container.addSublayer(containerChild)
        root.addSublayer(container)

        let front = CALayer()
        front.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        front.backgroundColor = UIColor.red.cgColor
        front.zPosition = 1
        root.addSublayer(front)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(result.sublayers.map(\.absoluteFrame) == [CGRect(x: 0, y: 0, width: 100, height: 100)])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Keeps visible children of a zero-sized container that does not clip")
    func keepsVisibleChildrenOfZeroSizedNonClippingContainer() throws {
        // Given
        let child = CALayerSnapshot.mockWith(
            replayID: 3,
            absoluteFrame: CGRect(x: 10, y: 10, width: 20, height: 20),
            backgroundColor: UIColor.red.cgColor
        )
        let container = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: .zero,
            sublayers: [child]
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [container])

        // When
        let result = try #require(root.removingOccluded())

        // Then
        let visibleContainer = try #require(result.sublayers.first)
        #expect(visibleContainer.sublayers.map(\.replayID) == [child.replayID])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not treat a rotated layer as an occluder")
    func doesNotTreatRotatedLayerAsOccluder() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let behind = CALayer()
        behind.frame = CGRect(x: 10, y: 10, width: 10, height: 10)
        behind.backgroundColor = UIColor.green.cgColor
        behind.zPosition = 0
        root.addSublayer(behind)

        let rotated = CALayer()
        rotated.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        rotated.backgroundColor = UIColor.red.cgColor
        rotated.transform = CATransform3DMakeRotation(.pi / 8, 0, 0, 1)
        rotated.zPosition = 1
        root.addSublayer(rotated)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(result.sublayers.map(\.absoluteFrame).contains(CGRect(x: 10, y: 10, width: 10, height: 10)))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not treat a descendant of a masked ancestor as an occluder")
    func doesNotTreatDescendantOfMaskedAncestorAsOccluder() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let parent = CALayer()
        parent.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        parent.mask = CALayer()
        parent.zPosition = 1

        let child = CALayer()
        child.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        child.backgroundColor = UIColor.red.cgColor

        parent.addSublayer(child)
        root.addSublayer(parent)

        let behind = CALayer()
        behind.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        behind.backgroundColor = UIColor.green.cgColor
        behind.zPosition = 0

        root.addSublayer(behind)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(
            result.sublayers.map(\.absoluteFrame) == [
                CGRect(x: 0, y: 0, width: 20, height: 20),
                CGRect(x: 0, y: 0, width: 100, height: 100),
            ]
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not treat descendants of an opacity-filtered ancestor as occluders")
    func doesNotTreatDescendantsOfOpacityFilteredAncestorAsOccluders() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let parent = CALayer()
        parent.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        parent.filters = [try NSObject.makeCAFilter(type: "glassBackground")]
        parent.zPosition = 1

        let child = CALayer()
        child.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        child.backgroundColor = UIColor.red.cgColor
        parent.addSublayer(child)
        root.addSublayer(parent)

        let behind = CALayer()
        behind.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        behind.backgroundColor = UIColor.green.cgColor
        behind.zPosition = 0
        root.addSublayer(behind)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(
            result.sublayers.map(\.absoluteFrame) == [
                CGRect(x: 0, y: 0, width: 20, height: 20),
                CGRect(x: 0, y: 0, width: 100, height: 100),
            ]
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not cull a layer in the corner area of a rounded occluder")
    func doesNotCullLayerInCornerAreaOfRoundedOccluder() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let front = CALayer()
        front.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        front.backgroundColor = UIColor.red.cgColor
        front.cornerRadius = 16
        front.zPosition = 1
        root.addSublayer(front)

        let behindCorner = CALayer()
        behindCorner.frame = CGRect(x: 0, y: 0, width: 4, height: 4)
        behindCorner.backgroundColor = UIColor.green.cgColor
        behindCorner.zPosition = 0
        root.addSublayer(behindCorner)

        // When
        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let result = try #require(snapshot.removingOccluded())

        // Then
        #expect(
            result.sublayers.map(\.absoluteFrame) == [
                CGRect(x: 0, y: 0, width: 4, height: 4),
                CGRect(x: 0, y: 0, width: 64, height: 64),
            ]
        )
    }
}
#endif
