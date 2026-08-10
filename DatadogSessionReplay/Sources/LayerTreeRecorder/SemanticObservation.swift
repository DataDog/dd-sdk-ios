/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

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
        case automaticCapsule
        case glassGroup
        case backdrop
        case liquidLens
        case portal(PortalSemantics)
        case scrollPocket(UIRectEdge)
        case background(UIColor?)
        case compositorSupport
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct PortalSemantics: Sendable, Equatable {
        let sourceReplayID: Int64
        let sourceRect: CGRect
        let matchesPosition: Bool
        let matchesTransform: Bool
        let matchesOpacity: Bool
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
        case embeddedContent(EmbeddedContentSemantics)
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

        init?(
            type: CAGradientLayerType,
            colors: [CGColor],
            locations: [CGFloat]?,
            startPoint: CGPoint,
            endPoint: CGPoint
        ) {
            guard
                colors.count >= 2,
                locations == nil || locations?.count == colors.count
            else {
                return nil
            }

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
    }
}

// MARK: - EmbeddedContentSemantics

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    struct EmbeddedContentSemantics: Sendable, Equatable {
        let slotID: String

        init(slotID: String) {
            self.slotID = slotID
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
    }
}
#endif
