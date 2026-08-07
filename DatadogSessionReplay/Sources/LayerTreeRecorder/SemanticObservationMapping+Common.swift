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

@_spi(Internal)
import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservationMapping {
    static let embeddedContent = Self { layer, _, context in
        guard
            let view = layer.delegate as? UIView,
            let slotID = view.dd.sessionReplaySlotID
        else {
            return nil
        }

        context.embeddedContentViewCache.add(view)

        return .init(
            semantics: .embeddedContent(.init(slotID: slotID)),
            ignoresSublayers: true
        )
    }

    static let gradient = Self { layer, _, _ in
        guard let gradientLayer = layer as? CAGradientLayer else {
            return nil
        }

        // Leaf masks are preserved by falling back to a content snapshot.
        guard gradientLayer.mask == nil || gradientLayer.sublayers?.isEmpty == false else {
            return nil
        }

        guard
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
        guard layer.isBarBackground else {
            return nil
        }

        return .init(semantics: .layer, ignoresImagePrivacy: true)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation.GradientSemantics {
    fileprivate init?(gradientLayer: CAGradientLayer) {
        guard let colorValues = gradientLayer.colors else {
            return nil
        }

        let colors = colorValues.compactMap(CGColor.safeCast)
        guard colors.count == colorValues.count else {
            return nil
        }

        let locations = gradientLayer.locations?.map { CGFloat(truncating: $0) }
        self.init(
            type: gradientLayer.type,
            colors: colors,
            locations: locations,
            startPoint: gradientLayer.startPoint,
            endPoint: gradientLayer.endPoint
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation.LabelSemantics {
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

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation.ImageSemantics {
    fileprivate init(imageView: UIImageView) {
        let image = imageView.isHighlighted ? imageView.highlightedImage ?? imageView.image : imageView.image

        self.init(
            hasContent: image != nil,
            isContextual: image?.isContextual ?? false
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation.TextInputSemantics {
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

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation.WebViewSemantics {
    fileprivate init(webView: WKWebView, absoluteFrame: CGRect) {
        self.init(
            slotID: webView.hash,
            slotFrame: webView.sessionReplayContentFrame(from: absoluteFrame)
        )
    }
}
#endif
