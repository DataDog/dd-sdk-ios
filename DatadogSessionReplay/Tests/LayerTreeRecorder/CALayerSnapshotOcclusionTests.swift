/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
import QuartzCore
import Testing
import UIKit

@testable import DatadogSessionReplay

@MainActor
struct CALayerSnapshotOcclusionTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Draws content when the layer has drawable contents")
    func drawsContentWhenLayerHasDrawableContents() throws {
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
    @Test(
        "Is not axis-aligned for transforms with rotation or perspective",
        arguments: [
            CATransform3DMakeRotation(.pi / 4, 0, 0, 1),
            CATransform3DMakeRotation(.pi / 4, 1, 0, 0),
            CATransform3DMakeRotation(.pi / 4, 0, 1, 0),
            {
                var transform = CATransform3DIdentity
                transform.m14 = -1 / 500
                return transform
            }(),
            {
                var transform = CATransform3DIdentity
                transform.m24 = -1 / 500
                return transform
            }(),
            {
                var transform = CATransform3DIdentity
                transform.m34 = -1 / 500
                return transform
            }(),
        ]
    )
    func isNotAxisAlignedForNonTrivialTransforms(transform: CATransform3D) throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.transform = transform

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(!snapshot.isAxisAligned)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is axis-aligned when scaled uniformly")
    func isAxisAlignedWhenScaledUniformly() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        layer.transform = CATransform3DMakeScale(2, 2, 1)

        // When
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // Then
        #expect(snapshot.isAxisAligned)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is an occluder when all conditions are met")
    func isOccluderWhenAllConditionsAreMet() throws {
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
    @Test("Is not an occluder when the transform is not axis-aligned")
    func isNotOccluderWhenTransformIsNotAxisAligned() throws {
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
}
#endif
