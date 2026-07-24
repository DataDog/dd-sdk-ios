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
            || observation.semantics == .visualEffect(.automaticCapsule)
            || filters.contains {
                SRCompositionLayerModifier(filter: $0, semantics: observation.semantics) != nil
            }
            || SRCompositionLayer.CompositeOperation(
                compositingFilter: compositingFilter,
                semantics: observation.semantics
            ) != nil
    }

    func modifiers(maskImageResourceID: String? = nil) -> [SRCompositionLayerModifier] {
        var result: [SRCompositionLayerModifier] = []

        // Modifiers order determines the final appearance in the player

        // Clipping
        if let clipModifier {
            result.append(clipModifier)
        }

        // Filters
        result.append(
            contentsOf: filters.compactMap {
                SRCompositionLayerModifier(filter: $0, semantics: observation.semantics)
            }
        )

        // Shadow
        if let shadowModifier {
            result.append(shadowModifier)
        }

        // Opacity
        if opacity < 1 {
            result.append(.compositionLayerOpacityModifier(value: .init(value: Double(opacity))))
        }

        // Mask
        if mask != nil, let maskImageResourceID {
            result.append(.compositionLayerMaskImageModifier(value: .init(resourceId: maskImageResourceID)))
        }

        return result
    }

    private var clipModifier: SRCompositionLayerModifier? {
        let cornerRadii: CornerRadii? = if case .visualEffect(.automaticCapsule) = observation.semantics {
            .init(
                cornerRadius: min(absoluteFrame.width, absoluteFrame.height) / 2,
                maskedCorners: [
                    .layerMinXMinYCorner,
                    .layerMaxXMinYCorner,
                    .layerMinXMaxYCorner,
                    .layerMaxXMaxYCorner
                ]
            )
        } else {
            masksToBounds ? self.cornerRadii : nil
        }

        return cornerRadii.map {
            .compositionLayerClipModifier(
                value: .init(
                    path: SwiftUI.Path(
                        roundedRect: .init(origin: .zero, size: absoluteFrame.size),
                        cornerRadii: $0,
                        cornerCurve: cornerCurve
                    ).dd.svgString
                )
            )
        }
    }

    private var shadowModifier: SRCompositionLayerModifier? {
        let shadow: SRCompositionLayerShadowModifier? = if case .visualEffect(.automaticCapsule) = observation.semantics {
            .init(
                color: hexString(from: UIColor.black.withAlphaComponent(0.125).cgColor) ?? .fallbackColor,
                offsetX: 0,
                offsetY: 0,
                radius: 8
            )
        } else if !masksToBounds, hasShadow, let shadowColor {
            .init(
                color: shadowColor
                    .copy(alpha: shadowColor.alpha * CGFloat(shadowOpacity))
                    .flatMap(hexString(from:)) ?? .fallbackColor,
                offsetX: Double(shadowOffset.width),
                offsetY: Double(shadowOffset.height),
                path: shadowPath.map {
                    SwiftUI.Path($0)
                        .applying(.init(translationX: -bounds.minX, y: -bounds.minY))
                        .dd.svgString
                },
                radius: Double(shadowRadius)
            )
        } else {
            nil
        }

        return shadow.map {
            .compositionLayerShadowModifier(value: $0)
        }
    }
}

extension SRCompositionLayer.CompositeOperation {
    @available(iOS 13.0, tvOS 13.0, *)
    init?(
        compositingFilter: CALayerSnapshot.CompositingFilter?,
        semantics: CALayerSnapshot.SemanticObservation.Semantics
    ) {
        if case .visualEffect(.scrollPocket) = semantics {
            self = .destinationOut
            return
        }

        guard let compositingFilter else {
            return nil
        }

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
    fileprivate init?(
        filter: CALayerSnapshot.Filter,
        semantics: CALayerSnapshot.SemanticObservation.Semantics
    ) {
        if case .visualEffect(.backdrop) = semantics,
           case .gaussianBlur = filter {
            return nil
        }

        switch filter {
        case .gaussianBlur(let radius):
            self = .compositionLayerGaussianBlurModifier(value: .init(radius: Double(radius)))
        case .colorMatrix(let colorMatrix):
            self = .compositionLayerColorMatrixModifier(value: .init(matrix: colorMatrix.values))
        case .vibrantColorMatrix(var colorMatrix):
            // Vibrant color matrices use compositor-specific alpha handling. We need to preserve
            // source alpha to avoid making transparent pixels opaque.
            colorMatrix.m41 = 0
            colorMatrix.m42 = 0
            colorMatrix.m43 = 0
            colorMatrix.m44 = 1
            colorMatrix.m45 = 0
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
