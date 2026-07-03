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

        /// When `true`, non-finite layer corner radii are resolved from the layer bounds.
        var usesAutomaticCornerRadius: Bool = false
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    enum Semantics: Sendable, Equatable {
        case layer
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
        switch layer.delegate {
        case _ as UIActivityIndicatorView:
            self.init(semantics: .layer, ignoresSublayers: true)
        case let label as UILabel where !label.hasAttributedText:
            // Attributed text falls through to layer semantics and will be rendered from the layer image.
            self.init(label: label)
        case let imageView as UIImageView:
            self.init(imageView: imageView)
        case let textView as UITextView:
            self.init(textView: textView)
        case let textField as UITextField:
            self.init(textField: textField)
        case _ as UISwitch, _ as UISlider:
            if #available(iOS 26.0, *) {
                // iOS 26 toggle and slider thumbs use a non-finite corner radius for their rounded thumb shape.
                self.init(semantics: .layer, usesAutomaticCornerRadius: true)
            } else {
                self.init(semantics: .layer)
            }
        case let webView as WKWebView:
            context.webViewCache.add(webView)
            self.init(webView: webView, absoluteFrame: absoluteFrame)
        default:
            self.init(semantics: .layer)
        }

        // Ignore image privacy for system UI chrome
        if layer.delegate is UIControl
            || layer.delegate is UIProgressView
            || layer.delegate?.isBarBackground == true {
            ignoresImagePrivacy = true
        }
    }
}

extension CALayerDelegate {
    fileprivate var isBarBackground: Bool {
        "\(type(of: self))" == "_UIBarBackground"
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
    }

    fileprivate init(label: UILabel) {
        self.init(
            semantics: .label(
                .init(
                    text: label.text,
                    textColor: label.textColor,
                    textAlignment: label.textAlignment,
                    font: label.font,
                    adjustsFontSizeToFitWidth: label.adjustsFontSizeToFitWidth,
                    lineBreakMode: label.lineBreakMode
                )
            ),
            ignoresSublayers: true
        )
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
    }

    fileprivate init(imageView: UIImageView) {
        let image = imageView.isHighlighted ? imageView.highlightedImage ?? imageView.image : imageView.image

        self.init(
            semantics: .image(
                .init(
                    hasContent: image != nil,
                    isContextual: image?.isContextual ?? false
                )
            ),
            ignoresSublayers: true
        )
    }
}

// MARK: - TextInputSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct TextInputSemantics: Sendable, Equatable {
        let isSensitiveText: Bool
        let isEditable: Bool
        let isEmpty: Bool
    }

    fileprivate init(textView: UITextView) {
        self.init(
            semantics: .textInput(
                .init(
                    isSensitiveText: textView.dd.isSensitiveText,
                    isEditable: textView.isEditable,
                    isEmpty: textView.text?.isEmpty ?? true
                )
            )
        )
    }

    fileprivate init(textField: UITextField) {
        self.init(
            semantics: .textInput(
                .init(
                    isSensitiveText: textField.dd.isSensitiveText,
                    isEditable: true,
                    isEmpty: textField.text?.isEmpty ?? true
                )
            )
        )
    }
}

// MARK: - WebViewSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct WebViewSemantics: Sendable, Equatable {
        let slotID: Int
        let slotFrame: CGRect
    }

    fileprivate init(webView: WKWebView, absoluteFrame: CGRect) {
        self.init(
            semantics: .webView(
                .init(
                    slotID: webView.hash,
                    slotFrame: webView.sessionReplayContentFrame(from: absoluteFrame)
                )
            ),
            ignoresSublayers: true
        )
    }
}
#endif
