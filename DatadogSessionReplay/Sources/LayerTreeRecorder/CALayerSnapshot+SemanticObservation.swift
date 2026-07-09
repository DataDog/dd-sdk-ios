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
    enum Semantics: Sendable, Equatable {
        case layer
        case visualEffect(VisualEffect)
        case label(LabelSemantics)
        case image(ImageSemantics)
        case textInput(TextInputSemantics)
        case webView(WebViewSemantics)
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

// MARK: - VisualEffect

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    enum VisualEffect: Sendable, Equatable {
        case liquidLens
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

extension UILabel {
    fileprivate var hasAttributedText: Bool {
        guard let attributedText else {
            return false
        }
        return attributedText.hasMultipleRuns
    }
}

extension NSAttributedString {
    fileprivate var hasMultipleRuns: Bool {
        guard length > 0 else {
            return false
        }

        var runCount = 0

        enumerateAttributes(in: NSRange(location: 0, length: length), options: []) { _, _, stop in
            runCount += 1

            if runCount > 1 {
                stop.pointee = true
            }
        }

        return runCount > 1
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
        .liquidLens,
    ]
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservationMapping {
    static let activityIndicator = Self { layer, _, _ in
        guard layer.delegate is UIActivityIndicatorView else {
            return nil
        }

        return .init(semantics: .layer, ignoresSublayers: true)
    }

    static let label = Self { layer, _, _ in
        guard let label = layer.delegate as? UILabel, !label.hasAttributedText else {
            // Labels with attributed text that has multiple attribute runs fall through to layer semantics
            // and will be rendered from the layer image.
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
    static let liquidLens = Self { layer, _, _ in
        guard layer.delegate?.isLiquidLens == true else {
            return nil
        }

        return .init(semantics: .visualEffect(.liquidLens))
    }
}

extension CALayerDelegate {
    fileprivate var isBarBackground: Bool {
        NSStringFromClass(type(of: self)) == "_UIBarBackground"
    }

    fileprivate var isLiquidLens: Bool {
        NSStringFromClass(type(of: self)) == "_UILiquidLensView"
    }
}
#endif
