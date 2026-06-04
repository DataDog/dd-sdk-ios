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
    /// Semantic meaning captured for a layer, plus the traversal decision for its sublayers.
    struct SemanticObservation: Sendable, Equatable {
        var semantics: Semantics

        /// When `true`, the semantic payload owns how this layer is represented and sublayers are not captured.
        var ignoreSublayers: Bool = false
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    enum Semantics: Sendable, Equatable {
        case layer
        case activityIndicator
        case label(LabelSemantics)
        case image(ImageSemantics)
        case progress(ProgressSemantics)
        case stepper(StepperSemantics)
        case text(TextSemantics)
        case textField(TextFieldSemantics)
        case switchControl(SwitchControlSemantics)
        case webView(WebViewSemantics)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    @MainActor
    init(layer: CALayer, context: CALayerSnapshot.Context) {
        switch layer.delegate {
        case _ as UIActivityIndicatorView:
            self.init(semantics: .activityIndicator, ignoreSublayers: true)
        case let label as UILabel where !label.hasAttributedText:
            // Attributed text falls through to layer semantics and will be rendered from the layer image.
            self.init(label: label)
        case let imageView as UIImageView:
            self.init(imageView: imageView)
        case let progressView as UIProgressView:
            self.init(progressView: progressView)
        case let stepper as UIStepper:
            self.init(stepper: stepper)
        case let textView as UITextView:
            self.init(textView: textView)
        case let textField as UITextField:
            self.init(textField: textField)
        case let switchControl as UISwitch:
            self.init(switchControl: switchControl)
        case let webView as WKWebView:
            context.webViewCache.add(webView)
            self.init(webView: webView)
        default:
            self.init(semantics: .layer)
        }
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
            ignoreSublayers: true
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
        let image: UIImage?
        let highlightedImage: UIImage?
        let isHighlighted: Bool
        let tintColor: UIColor?
    }

    fileprivate init(imageView: UIImageView) {
        self.init(
            semantics: .image(
                .init(
                    image: imageView.image,
                    highlightedImage: imageView.highlightedImage,
                    isHighlighted: imageView.isHighlighted,
                    tintColor: imageView.tintColor
                )
            ),
            ignoreSublayers: true
        )
    }
}

// MARK: - ProgressSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct ProgressSemantics: Sendable, Equatable {
        let progress: Float
    }

    fileprivate init(progressView: UIProgressView) {
        self.init(
            semantics: .progress(.init(progress: progressView.progress)),
            ignoreSublayers: true
        )
    }
}

// MARK: - StepperSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct StepperSemantics: Sendable, Equatable {
        let value: Double
    }

    fileprivate init(stepper: UIStepper) {
        self.init(
            semantics: .stepper(.init(value: stepper.value)),
            ignoreSublayers: true
        )
    }
}

// MARK: - TextSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct TextSemantics: Sendable, Equatable {
        let text: String?
        let isEditable: Bool
        let isSensitiveText: Bool
    }

    fileprivate init(textView: UITextView) {
        self.init(
            semantics: .text(
                .init(
                    text: textView.text,
                    isEditable: textView.isEditable,
                    isSensitiveText: textView.dd.isSensitiveText
                )
            ),
            ignoreSublayers: true
        )
    }
}

// MARK: - TextFieldSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct TextFieldSemantics: Sendable, Equatable {
        let text: String?
        let placeholder: String?
        let isSensitiveText: Bool
    }

    fileprivate init(textField: UITextField) {
        self.init(
            semantics: .textField(
                .init(
                    text: textField.text,
                    placeholder: textField.placeholder,
                    isSensitiveText: textField.dd.isSensitiveText
                )
            )
        )
    }
}

// MARK: - SwitchControlSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct SwitchControlSemantics: Sendable, Equatable {
        let isOn: Bool
    }

    fileprivate init(switchControl: UISwitch) {
        self.init(
            semantics: .switchControl(.init(isOn: switchControl.isOn)),
            ignoreSublayers: true
        )
    }
}

// MARK: - WebViewSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct WebViewSemantics: Sendable, Equatable {
        let slotID: Int
    }

    fileprivate init(webView: WKWebView) {
        self.init(
            semantics: .webView(.init(slotID: webView.hash)),
            ignoreSublayers: true
        )
    }
}
#endif
