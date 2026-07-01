/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import Testing
import UIKit

@_spi(Internal)
@testable import DatadogSessionReplay

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
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 5
        layer.opacity = 0.5

        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        // When
        let modifiers = snapshot.modifiers()

        // Then
        #expect(snapshot.requiresCompositionLayer)
        #expect(modifierTypes(modifiers) == ["clip", "brightnessBias", "shadow", "opacity"])
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
            case .compositionLayerBackgroundMaterialModifier:
                "backgroundMaterial"
            }
        }
    }
}
#endif
