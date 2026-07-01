/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import SwiftUI

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    var requiresCompositionLayer: Bool {
        masksToBounds
            || opacity < 1
            || hasShadow
            || filters.contains(where: { SRCompositionLayerModifier(filter: $0) != nil })
            || compositingFilter.flatMap(SRCompositionLayer.CompositeOperation.init(compositingFilter:)) != nil
    }

    func modifiers() -> [SRCompositionLayerModifier] {
        var result: [SRCompositionLayerModifier] = []

        // Modifiers order determines the final appearance in the player

        // Clipping
        if masksToBounds {
            result.append(
                .compositionLayerClipModifier(
                    value: .init(
                        path: SwiftUI.Path(
                            roundedRect: .init(origin: .zero, size: absoluteFrame.size),
                            cornerRadii: cornerRadii,
                            cornerCurve: cornerCurve
                        ).dd.svgString
                    )
                )
            )
        }

        // Filters
        result.append(
            contentsOf: filters.compactMap(SRCompositionLayerModifier.init(filter:))
        )

        // Shadow
        if let shadowModifier {
            result.append(shadowModifier)
        }

        // Opacity
        if opacity < 1 {
            result.append(.compositionLayerOpacityModifier(value: .init(value: Double(opacity))))
        }

        return result
    }

    private var shadowModifier: SRCompositionLayerModifier? {
        guard
            hasShadow,
            let shadowColor,
            let effectiveColor = shadowColor.copy(alpha: shadowColor.alpha * CGFloat(shadowOpacity)),
            let color = hexString(from: effectiveColor)
        else {
            return nil
        }

        let path = shadowPath.map {
            SwiftUI.Path($0)
                .applying(.init(translationX: -bounds.minX, y: -bounds.minY))
                .dd.svgString
        }

        return .compositionLayerShadowModifier(
            value: .init(
                color: color,
                offsetX: Double(shadowOffset.width),
                offsetY: Double(shadowOffset.height),
                path: path,
                radius: Double(shadowRadius)
            )
        )
    }
}

extension SRCompositionLayer.CompositeOperation {
    @available(iOS 13.0, tvOS 13.0, *)
    init?(compositingFilter: CALayerSnapshot.CompositingFilter) {
        switch compositingFilter {
        case .destinationIn:
            self = .destinationIn
        case .plusDarker:
            self = .plusDarker
        default:
            return nil
        }
    }
}

extension SRCompositionLayerModifier {
    @available(iOS 13.0, tvOS 13.0, *)
    fileprivate init?(filter: CALayerSnapshot.Filter) {
        switch filter {
        case .glassBackground:
            self = .compositionLayerBackgroundMaterialModifier(value: .init(kind: .glass))
        case .gaussianBlur(let radius):
            self = .compositionLayerGaussianBlurModifier(value: .init(radius: Double(radius)))
        case .colorMatrix(let colorMatrix):
            self = .compositionLayerColorMatrixModifier(value: .init(matrix: colorMatrix.values))
        case .saturate(let value):
            self = .compositionLayerSaturateModifier(value: .init(value: value))
        case .brightness(let value):
            self = .compositionLayerBrightnessBiasModifier(value: .init(value: value))
        case .multiplyColor(let color):
            guard let colorMatrix = CALayerSnapshot.ColorMatrix(multiplyColor: color) else {
                return nil
            }
            self = .compositionLayerColorMatrixModifier(value: .init(matrix: colorMatrix.values))
        case .unknown:
            return nil
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.ColorMatrix {
    fileprivate var values: [Double] {
        [
            m11, m12, m13, m14, m15,
            m21, m22, m23, m24, m25,
            m31, m32, m33, m34, m35,
            m41, m42, m43, m44, m45
        ].map(Double.init)
    }

    fileprivate init?(multiplyColor color: CGColor) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1

        guard (UIColor(cgColor: color)).getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return nil
        }

        self.init(
            m11: Float(r),
            m22: Float(g),
            m33: Float(b),
            m44: Float(a)
        )
    }
}
#endif
