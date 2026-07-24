/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import TestUtilities
import QuartzCore
import SwiftUI
import Testing
import UIKit

@_spi(Internal)
@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct CALayerSnapshotSRCompositionLayerTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates modifiers in rendering order")
    func createsModifiersInRenderingOrder() throws {
        // Given
        let filter = try NSObject.makeCAFilter(type: "colorBrightness")
        filter.setValue(CGFloat(0.25), forKey: "inputAmount")

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        layer.masksToBounds = true
        layer.filters = [filter]
        layer.shadowColor = UIColor.black.cgColor // Shadow modifier is suppressed with masksToBounds == true
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 5
        layer.opacity = 0.5

        let maskLayer = CALayer()
        maskLayer.bounds = layer.bounds
        maskLayer.backgroundColor = UIColor.black.cgColor
        layer.mask = maskLayer

        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let resourceID = "mask-resource-id"

        // When
        let modifiers = snapshot.modifiers(maskImageResourceID: resourceID)

        // Then
        #expect(snapshot.requiresCompositionLayer)
        #expect(modifierTypes(modifiers) == ["clip", "brightnessBias", "opacity", "maskImage"])

        let modifier = try #require(modifiers.last)
        guard case .compositionLayerMaskImageModifier(let maskImageModifier) = modifier else {
            Issue.record("Expected a mask image modifier")
            return
        }

        #expect(maskImageModifier.resourceId == resourceID)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Maps shadows to shadow modifiers")
    func mapsShadowsToShadowModifiers() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 2, height: 3)
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 4

        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // When
        let modifiers = snapshot.modifiers()

        // Then
        let modifier = try #require(modifiers.first)
        guard case .compositionLayerShadowModifier(let shadow) = modifier else {
            Issue.record("Expected a shadow modifier")
            return
        }

        #expect(snapshot.requiresCompositionLayer)
        #expect(modifiers.count == 1)
        #expect(shadow.color == "#00000080")
        #expect(shadow.offsetX == 2)
        #expect(shadow.offsetY == 3)
        #expect(shadow.radius == 4)
        #expect(shadow.path == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Maps automatic capsule effect to clip and shadow modifiers")
    func mapsAutomaticCapsuleEffectToClipAndShadowModifiers() throws {
        // Given
        let frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        let snapshot = CALayerSnapshot.mockWith(
            absoluteFrame: frame,
            observation: .init(semantics: .visualEffect(.automaticCapsule))
        )
        let cornerRadii = CALayerSnapshot.CornerRadii(
            cornerRadius: 20,
            maskedCorners: [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
        )
        let expectedClipPath = SwiftUI.Path(
            roundedRect: CGRect(origin: .zero, size: frame.size),
            cornerRadii: cornerRadii,
            cornerCurve: .circular
        ).dd.svgString

        // When
        let modifiers = snapshot.modifiers()

        // Then
        #expect(snapshot.requiresCompositionLayer)
        #expect(modifierTypes(modifiers) == ["clip", "shadow"])

        let firstModifier = try #require(modifiers.first)
        let lastModifier = try #require(modifiers.last)
        guard case .compositionLayerClipModifier(let clip) = firstModifier,
              case .compositionLayerShadowModifier(let shadow) = lastModifier else {
            Issue.record("Expected clip and shadow modifiers")
            return
        }

        #expect(clip.path == expectedClipPath)
        #expect(shadow.color == hexString(from: UIColor.black.withAlphaComponent(0.125).cgColor))
        #expect(shadow.offsetX == 0)
        #expect(shadow.offsetY == 0)
        #expect(shadow.radius == 8)
        #expect(shadow.path == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Maps multiply color filters to color matrix modifiers")
    func mapsMultiplyColorFiltersToColorMatrixModifiers() throws {
        // Given
        let filter = try NSObject.makeCAFilter(type: "multiplyColor")
        filter.setValue(CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.8), forKey: "inputColor")

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        layer.filters = [filter]

        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // When
        let modifiers = snapshot.modifiers()

        // Then
        let modifier = try #require(modifiers.first)
        guard case .compositionLayerColorMatrixModifier(let colorMatrix) = modifier else {
            Issue.record("Expected a color matrix modifier")
            return
        }

        #expect(snapshot.requiresCompositionLayer)
        #expect(colorMatrix.matrix.count == 20)
        #expect(colorMatrix.matrix[0] > 0)
        #expect(colorMatrix.matrix[6] > 0)
        #expect(colorMatrix.matrix[12] > 0)
        #expect(colorMatrix.matrix[18] > 0)
        #expect(colorMatrix.matrix.enumerated().allSatisfy { index, value in
            [0, 6, 12, 18].contains(index) || value == 0
        })
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Maps vibrant color matrix filters while preserving source alpha")
    func mapsVibrantColorMatrixFiltersPreservingSourceAlpha() throws {
        // Given
        // swiftlint:disable multiline_arguments
        let matrix = CALayerSnapshot.ColorMatrix(
            m11: 1, m12: 2, m13: 3, m14: 4, m15: 5,
            m21: 6, m22: 7, m23: 8, m24: 9, m25: 10,
            m31: 11, m32: 12, m33: 13, m34: 14, m35: 15,
            m41: 16, m42: 17, m43: 18, m44: 19, m45: 20
        )
        // swiftlint:enable multiline_arguments
        let snapshot = CALayerSnapshot.mockWith(filters: [.vibrantColorMatrix(matrix)])

        // When
        let modifiers = snapshot.modifiers()

        // Then
        let modifier = try #require(modifiers.first)
        guard case .compositionLayerColorMatrixModifier(let colorMatrix) = modifier else {
            Issue.record("Expected a color matrix modifier")
            return
        }

        #expect(colorMatrix.matrix == [
            1, 2, 3, 4, 5,
            6, 7, 8, 9, 10,
            11, 12, 13, 14, 15,
            0, 0, 0, 1, 0
        ])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Maps Gaussian blur only for regular layers")
    func mapsGaussianBlurOnlyForRegularLayers() {
        // Given
        let regularLayer = CALayerSnapshot.mockWith(filters: [.gaussianBlur(12)])
        let backdropLayer = CALayerSnapshot.mockWith(
            observation: .init(semantics: .visualEffect(.backdrop)),
            filters: [.gaussianBlur(12)]
        )

        // When
        let regularLayerModifiers = regularLayer.modifiers()
        let backdropLayerModifiers = backdropLayer.modifiers()

        // Then
        #expect(regularLayer.requiresCompositionLayer)
        #expect(modifierTypes(regularLayerModifiers) == ["gaussianBlur"])
        #expect(!backdropLayer.requiresCompositionLayer)
        #expect(backdropLayerModifiers.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Maps scroll pocket effects to destination-out compositing")
    func mapsScrollPocketEffectsToDestinationOutCompositing() {
        // Given
        let snapshot = CALayerSnapshot.mockWith(
            observation: .init(semantics: .visualEffect(.scrollPocket(.top)))
        )

        // When
        let compositeOperation = SRCompositionLayer.CompositeOperation(
            compositingFilter: snapshot.compositingFilter,
            semantics: snapshot.observation.semantics
        )

        // Then
        #expect(compositeOperation == .destinationOut)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private func modifierTypes(_ modifiers: [SRCompositionLayerModifier]) -> [String] {
        modifiers.map { modifier in
            switch modifier {
            case .compositionLayerClipModifier:
                "clip"
            case .compositionLayerOpacityModifier:
                "opacity"
            case .compositionLayerColorMatrixModifier:
                "colorMatrix"
            case .compositionLayerGaussianBlurModifier:
                "gaussianBlur"
            case .compositionLayerShadowModifier:
                "shadow"
            case .compositionLayerBrightnessBiasModifier:
                "brightnessBias"
            case .compositionLayerSaturateModifier:
                "saturate"
            case .compositionLayerMaskImageModifier:
                "maskImage"
            }
        }
    }
}
#endif
