/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore
import UIKit
import WebKit

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    /// Semantic meaning captured for a layer, plus capture hints for its sublayers.
    struct SemanticObservation: Sendable, Equatable {
        var semantics: Semantics

        /// When `true`, the semantic payload owns how this layer is represented and sublayers are not captured.
        var ignoresSublayers: Bool = false

        /// When `true`, image privacy does not apply to image snapshots captured from this layer or its sublayers.
        var ignoresImagePrivacy: Bool = false
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    enum VisualEffect: Sendable, Equatable {
        case glassGroup
        case liquidLens
        case background(UIColor?)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    enum Semantics: Sendable, Equatable {
        case layer
        case gradient(GradientSemantics)
        case visualEffect(VisualEffect)
        case label(LabelSemantics)
        case image(ImageSemantics)
        case textInput(TextInputSemantics)
        case webView(WebViewSemantics)
    }
}

// MARK: - GradientSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct GradientSemantics: Sendable, Equatable {
        let type: CAGradientLayerType
        let colors: [CGColor]
        let locations: [CGFloat]?
        let startPoint: CGPoint
        let endPoint: CGPoint

        init(
            type: CAGradientLayerType,
            colors: [CGColor],
            locations: [CGFloat]?,
            startPoint: CGPoint,
            endPoint: CGPoint
        ) {
            self.type = type
            self.colors = colors
            self.locations = locations
            self.startPoint = startPoint
            self.endPoint = endPoint
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    @MainActor
    init(layer: CALayer, context: CALayerSnapshot.Context) {
        self.init(layer: layer, absoluteFrame: layer.frame, context: context)
    }

    @MainActor
    init(layer: CALayer, absoluteFrame: CGRect, context: CALayerSnapshot.Context) {
        self = CALayerSnapshot.SemanticObservationMapping.allCases
            .lazy
            .compactMap { $0.observe(layer, absoluteFrame, context) }
            .first ?? .init(semantics: .layer)
    }
}

// MARK: - LabelSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct LabelSemantics: Sendable, Equatable {
        let text: String?
        let textColor: UIColor?
        let textAlignment: NSTextAlignment
        let font: UIFont?
        let adjustsFontSizeToFitWidth: Bool
        let lineBreakMode: NSLineBreakMode

        init(
            text: String?,
            textColor: UIColor?,
            textAlignment: NSTextAlignment,
            font: UIFont?,
            adjustsFontSizeToFitWidth: Bool,
            lineBreakMode: NSLineBreakMode
        ) {
            self.text = text
            self.textColor = textColor
            self.textAlignment = textAlignment
            self.font = font
            self.adjustsFontSizeToFitWidth = adjustsFontSizeToFitWidth
            self.lineBreakMode = lineBreakMode
        }

        fileprivate init(label: UILabel) {
            self.init(
                text: label.text,
                textColor: label.textColor,
                textAlignment: label.textAlignment,
                font: label.font,
                adjustsFontSizeToFitWidth: label.adjustsFontSizeToFitWidth,
                lineBreakMode: label.lineBreakMode
            )
        }
    }
}

// MARK: - ImageSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct ImageSemantics: Sendable, Equatable {
        let hasContent: Bool
        let isContextual: Bool

        init(hasContent: Bool, isContextual: Bool) {
            self.hasContent = hasContent
            self.isContextual = isContextual
        }

        fileprivate init(imageView: UIImageView) {
            let image = imageView.isHighlighted ? imageView.highlightedImage ?? imageView.image : imageView.image

            self.init(
                hasContent: image != nil,
                isContextual: image?.isContextual ?? false
            )
        }
    }
}

// MARK: - TextInputSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct TextInputSemantics: Sendable, Equatable {
        let isSensitiveText: Bool
        let isEditable: Bool
        let isEmpty: Bool

        init(isSensitiveText: Bool, isEditable: Bool, isEmpty: Bool) {
            self.isSensitiveText = isSensitiveText
            self.isEditable = isEditable
            self.isEmpty = isEmpty
        }

        fileprivate init(textView: UITextView) {
            self.init(
                isSensitiveText: textView.dd.isSensitiveText,
                isEditable: textView.isEditable,
                isEmpty: textView.text?.isEmpty ?? true
            )
        }

        fileprivate init(textField: UITextField) {
            self.init(
                isSensitiveText: textField.dd.isSensitiveText,
                isEditable: true,
                isEmpty: textField.text?.isEmpty ?? true
            )
        }
    }
}

// MARK: - WebViewSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct WebViewSemantics: Sendable, Equatable {
        let slotID: Int
        let slotFrame: CGRect

        init(slotID: Int, slotFrame: CGRect) {
            self.slotID = slotID
            self.slotFrame = slotFrame
        }

        fileprivate init(webView: WKWebView, absoluteFrame: CGRect) {
            self.init(
                slotID: webView.hash,
                slotFrame: webView.sessionReplayContentFrame(from: absoluteFrame)
            )
        }
    }
}

// MARK: - SemanticObservationMapping

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    fileprivate struct SemanticObservationMapping {
        let observe: @MainActor (
            _ layer: CALayer,
            _ absoluteFrame: CGRect,
            _ context: CALayerSnapshot.Context
        ) -> SemanticObservation?
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservationMapping: CaseIterable {
    static let allCases: [Self] = [
        .gradient,
        .activityIndicator,
        .label,
        .imageView,
        .textView,
        .textField,
        .webView,
        .control,
        .progressView,
        .barBackground,
        // visual effects
        .glassGroup,
        .visualEffectBackground,
        .liquidLens
    ]
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservationMapping {
    static let gradient = Self { layer, _, _ in
        guard
            let gradientLayer = layer as? CAGradientLayer,
            gradientLayer.type == .axial,
            let gradient = CALayerSnapshot.SemanticObservation.GradientSemantics(gradientLayer: gradientLayer)
        else {
            return nil
        }

        return .init(semantics: .gradient(gradient))
    }

    static let activityIndicator = Self { layer, _, _ in
        guard layer.delegate is UIActivityIndicatorView else {
            return nil
        }

        return .init(semantics: .layer, ignoresSublayers: true)
    }

    static let label = Self { layer, _, _ in
        guard let label = layer.delegate as? UILabel, label.isTextWireframeRepresentable() else {
            // Labels that cannot be represented as a text wireframe fall through to layer semantics.
            return nil
        }

        return .init(semantics: .label(.init(label: label)), ignoresSublayers: true)
    }

    static let imageView = Self { layer, _, _ in
        guard let imageView = layer.delegate as? UIImageView else {
            return nil
        }

        return .init(semantics: .image(.init(imageView: imageView)), ignoresSublayers: true)
    }

    static let textView = Self { layer, _, _ in
        guard let textView = layer.delegate as? UITextView else {
            return nil
        }

        return .init(semantics: .textInput(.init(textView: textView)))
    }

    static let textField = Self { layer, _, _ in
        guard let textField = layer.delegate as? UITextField else {
            return nil
        }

        return .init(
            semantics: .textInput(.init(textField: textField)),
            ignoresImagePrivacy: true
        )
    }

    static let webView = Self { layer, absoluteFrame, context in
        guard let webView = layer.delegate as? WKWebView else {
            return nil
        }

        context.webViewCache.add(webView)

        return .init(
            semantics: .webView(.init(webView: webView, absoluteFrame: absoluteFrame)),
            ignoresSublayers: true
        )
    }

    static let control = Self { layer, _, _ in
        guard layer.delegate is UIControl else {
            return nil
        }

        return .init(semantics: .layer, ignoresImagePrivacy: true)
    }

    static let progressView = Self { layer, _, _ in
        guard layer.delegate is UIProgressView else {
            return nil
        }

        return .init(semantics: .layer, ignoresImagePrivacy: true)
    }

    static let barBackground = Self { layer, _, _ in
        guard layer.delegate?.isBarBackground == true else {
            return nil
        }

        return .init(semantics: .layer, ignoresImagePrivacy: true)
    }
}

// MARK: - VisualEffect mappings

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservationMapping {
    static let glassGroup = Self { layer, _, _ in
        guard layer.delegate?.isGlassGroup == true else {
            return nil
        }

        return .init(semantics: .visualEffect(.glassGroup), ignoresSublayers: true)
    }

    static let liquidLens = Self { layer, _, _ in
        guard layer.delegate?.isLiquidLens == true else {
            return nil
        }

        return .init(semantics: .visualEffect(.liquidLens))
    }

    static let visualEffectBackground = Self { layer, _, _ in
        guard layer.delegate?.isVisualEffectBackground == true else {
            return nil
        }

        // Visual effect containers may store their fallback background on the owning view
        let color: UIColor? = layer.superlayer
            .flatMap { superlayer in
                guard
                    let superview = superlayer.delegate as? UIView,
                    superview.bounds.size == layer.bounds.size,
                    let backgroundColor = superview.backgroundColor,
                    backgroundColor.cgColor.alpha > 0
                else {
                    return nil
                }
                return backgroundColor
            }

        return .init(
            semantics: .visualEffect(.background(color)),
            ignoresSublayers: true
        )
    }
}

extension CALayerDelegate {
    fileprivate var isBarBackground: Bool {
        NSStringFromClass(type(of: self)) == "_UIBarBackground"
    }

    fileprivate var isGlassGroup: Bool {
        NSStringFromClass(type(of: self)) == "UIKit._GlassGroupView"
    }

    fileprivate var isLiquidLens: Bool {
        NSStringFromClass(type(of: self)) == "_UILiquidLensView"
    }

    fileprivate var isVisualEffectBackground: Bool {
        NSStringFromClass(type(of: self)) == "_UIVisualEffectBackgroundView"
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation.GradientSemantics {
    fileprivate init?(gradientLayer: CAGradientLayer) {
        guard
            let colorValues = gradientLayer.colors,
            colorValues.count >= 2
        else {
            return nil
        }

        let colors = colorValues.compactMap(CGColor.safeCast)
        guard colors.count == colorValues.count else {
            return nil
        }

        let locations = gradientLayer.locations?.map { CGFloat(truncating: $0) }
        guard locations == nil || locations?.count == colors.count else {
            return nil
        }

        self.init(
            type: gradientLayer.type,
            colors: colors,
            locations: locations,
            startPoint: gradientLayer.startPoint,
            endPoint: gradientLayer.endPoint
        )
    }
}
#endif
