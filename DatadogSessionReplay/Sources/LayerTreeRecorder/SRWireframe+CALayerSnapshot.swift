/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import Foundation
import UIKit

extension SRWireframe {
    @available(iOS 13.0, tvOS 13.0, *)
    init(hiddenEmbeddedContentReplayID replayID: Int64, slotID: String) {
        self = .embeddedContentWireframe(
            value: .init(
                replayID: replayID,
                slotId: slotID,
                x: 0,
                y: 0,
                width: 0,
                height: 0,
                isVisible: false
            )
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    init(hiddenWebViewSlotID slotID: Int) {
        self = .webviewWireframe(
            value: .init(
                height: 0,
                id: Int64(slotID),
                isVisible: false,
                slotId: String(slotID),
                width: 0,
                x: 0,
                y: 0
            )
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    init?(
        layerSnapshot: CALayerSnapshot,
        backgroundGradient: SRShapeGradient? = nil,
        cornerRadius: CGFloat? = nil
    ) {
        guard layerSnapshot.hasBackgroundColor || layerSnapshot.hasBorder || backgroundGradient != nil else {
            return nil
        }

        self = .shapeWireframe(
            value: .init(
                replayID: layerSnapshot.replayID,
                x: Int64.ddWithNoOverflow(layerSnapshot.absoluteFrame.minX),
                y: Int64.ddWithNoOverflow(layerSnapshot.absoluteFrame.minY),
                width: Int64.ddWithNoOverflow(dimension: layerSnapshot.absoluteFrame.width),
                height: Int64.ddWithNoOverflow(dimension: layerSnapshot.absoluteFrame.height),
                border: .init(layerSnapshot: layerSnapshot),
                shapeStyle: .init(
                    layerSnapshot: layerSnapshot,
                    backgroundGradient: backgroundGradient,
                    cornerRadius: cornerRadius
                )
            )
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    init(
        layerSnapshot: CALayerSnapshot,
        backgroundColor: UIColor,
        cornerRadius: CGFloat? = nil
    ) {
        self = .shapeWireframe(
            value: .init(
                replayID: layerSnapshot.replayID,
                x: Int64.ddWithNoOverflow(layerSnapshot.absoluteFrame.minX),
                y: Int64.ddWithNoOverflow(layerSnapshot.absoluteFrame.minY),
                width: Int64.ddWithNoOverflow(dimension: layerSnapshot.absoluteFrame.width),
                height: Int64.ddWithNoOverflow(dimension: layerSnapshot.absoluteFrame.height),
                shapeStyle: .init(
                    backgroundColor: hexString(from: backgroundColor.cgColor) ?? .fallbackColor,
                    cornerRadius: (cornerRadius ?? layerSnapshot.cornerRadii.uniformCornerRadius)
                        .map(Double.init)
                )
            )
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    init?(
        layerSnapshot: CALayerSnapshot,
        label: CALayerSnapshot.SemanticObservation.LabelSemantics,
        cornerRadius: CGFloat? = nil
    ) {
        let text = layerSnapshot.textAndInputPrivacyLevel.staticTextObfuscator.mask(text: label.text ?? "")
        let hasVisibleText = !text.isEmpty
        let hasVisibleAppearance = layerSnapshot.hasBackgroundColor || layerSnapshot.hasBorder

        guard hasVisibleText || hasVisibleAppearance else {
            return nil
        }

        self = .textWireframe(
            value: .init(
                replayID: layerSnapshot.replayID,
                x: Int64.ddWithNoOverflow(layerSnapshot.absoluteFrame.minX),
                y: Int64.ddWithNoOverflow(layerSnapshot.absoluteFrame.minY),
                height: Int64.ddWithNoOverflow(dimension: layerSnapshot.absoluteFrame.height),
                width: Int64.ddWithNoOverflow(dimension: layerSnapshot.absoluteFrame.width),
                text: text,
                textStyle: .init(label: label, frame: layerSnapshot.absoluteFrame),
                border: .init(layerSnapshot: layerSnapshot),
                shapeStyle: .init(layerSnapshot: layerSnapshot, cornerRadius: cornerRadius),
                textPosition: .init(label: label)
            )
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    init(
        replayID: Int64,
        imageSnapshot: ContentSnapshot,
        resource: Resource
    ) {
        self = .imageWireframe(
            value: .init(
                replayID: replayID,
                x: Int64.ddWithNoOverflow(imageSnapshot.frame.minX),
                y: Int64.ddWithNoOverflow(imageSnapshot.frame.minY),
                width: Int64.ddWithNoOverflow(dimension: imageSnapshot.frame.width),
                height: Int64.ddWithNoOverflow(dimension: imageSnapshot.frame.height),
                isEmpty: false,
                mimeType: resource.mimeType,
                resourceId: resource.calculateIdentifier(),
            )
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    init(
        placeholderFor layerSnapshot: CALayerSnapshot,
        label: String
    ) {
        self = .placeholderWireframe(
            value: .init(
                replayID: layerSnapshot.replayID,
                x: Int64.ddWithNoOverflow(layerSnapshot.absoluteFrame.minX),
                y: Int64.ddWithNoOverflow(layerSnapshot.absoluteFrame.minY),
                width: Int64.ddWithNoOverflow(dimension: layerSnapshot.absoluteFrame.width),
                height: Int64.ddWithNoOverflow(dimension: layerSnapshot.absoluteFrame.height),
                label: label
            )
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    init(
        layerSnapshot: CALayerSnapshot,
        embeddedContent: CALayerSnapshot.SemanticObservation.EmbeddedContentSemantics
    ) {
        self = .embeddedContentWireframe(
            value: .init(
                replayID: layerSnapshot.replayID,
                slotId: embeddedContent.slotID,
                x: Int64.ddWithNoOverflow(layerSnapshot.absoluteFrame.minX),
                y: Int64.ddWithNoOverflow(layerSnapshot.absoluteFrame.minY),
                width: Int64.ddWithNoOverflow(dimension: layerSnapshot.absoluteFrame.width),
                height: Int64.ddWithNoOverflow(dimension: layerSnapshot.absoluteFrame.height),
                border: .init(layerSnapshot: layerSnapshot),
                isVisible: true,
                shapeStyle: .init(layerSnapshot: layerSnapshot)
            )
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    init(
        layerSnapshot: CALayerSnapshot,
        webView: CALayerSnapshot.SemanticObservation.WebViewSemantics
    ) {
        self = .webviewWireframe(
            value: .init(
                border: .init(layerSnapshot: layerSnapshot),
                height: Int64.ddWithNoOverflow(dimension: webView.slotFrame.height),
                id: Int64(webView.slotID),
                isVisible: true,
                shapeStyle: .init(layerSnapshot: layerSnapshot),
                slotId: String(webView.slotID),
                width: Int64.ddWithNoOverflow(dimension: webView.slotFrame.width),
                x: Int64.ddWithNoOverflow(webView.slotFrame.minX),
                y: Int64.ddWithNoOverflow(webView.slotFrame.minY)
            )
        )
    }
}

extension SRTextPosition {
    @available(iOS 13.0, tvOS 13.0, *)
    fileprivate init(label: CALayerSnapshot.SemanticObservation.LabelSemantics) {
        self.init(
            alignment: .init(systemTextAlignment: label.textAlignment)
        )
    }
}

extension SRTextStyle {
    @available(iOS 13.0, tvOS 13.0, *)
    fileprivate init(
        label: CALayerSnapshot.SemanticObservation.LabelSemantics,
        frame: CGRect
    ) {
        var fontSize = Int64.ddWithNoOverflow(label.font?.pointSize ?? .fallbackFontSize)

        if let text = label.text, !text.isEmpty, label.adjustsFontSizeToFitWidth {
            let calculatedFontSize = Int64(sqrt(frame.width * frame.height / CGFloat(text.count)))

            if calculatedFontSize < fontSize {
                fontSize = calculatedFontSize
            }
        }

        self.init(
            color: label.textColor.flatMap { hexString(from: $0.cgColor) } ?? .fallbackColor,
            family: .fallbackFontFamily,
            size: fontSize,
            truncationMode: .init(label.lineBreakMode)
        )
    }
}

extension SRShapeBorder {
    @available(iOS 13.0, tvOS 13.0, *)
    fileprivate init?(layerSnapshot: CALayerSnapshot) {
        guard
            let borderColor = layerSnapshot.borderColor,
            layerSnapshot.borderWidth > 0
        else {
            return nil
        }
        self.init(
            color: hexString(from: borderColor) ?? .fallbackColor,
            width: Int64.ddWithNoOverflow(layerSnapshot.borderWidth.rounded(.up))
        )
    }
}

extension SRShapeStyle {
    @available(iOS 13.0, tvOS 13.0, *)
    fileprivate init?(
        layerSnapshot: CALayerSnapshot,
        backgroundGradient: SRShapeGradient? = nil,
        cornerRadius: CGFloat? = nil
    ) {
        guard layerSnapshot.backgroundColor != nil || backgroundGradient != nil else {
            return nil
        }
        self.init(
            backgroundColor: layerSnapshot.backgroundColor.map {
                hexString(from: $0) ?? .fallbackColor
            },
            backgroundGradient: backgroundGradient,
            cornerRadius: (cornerRadius ?? layerSnapshot.cornerRadii.uniformCornerRadius)
                .map(Double.init)
        )
    }
}

extension SRShapeGradient {
    @available(iOS 13.0, tvOS 13.0, *)
    init?(
        gradient: CALayerSnapshot.SemanticObservation.GradientSemantics
    ) {
        guard gradient.type == .axial else {
            return nil
        }

        let locations = gradient.locations ?? gradient.colors.indices.map {
            CGFloat($0) / CGFloat(gradient.colors.count - 1)
        }
        let stops = zip(gradient.colors, locations).map { color, location in
            SRShapeGradientStop(
                color: hexString(from: color) ?? .fallbackColor,
                position: Double(location)
            )
        }

        self = .linear(
            value: .init(
                endPoint: .init(
                    x: Double(gradient.endPoint.x),
                    y: Double(gradient.endPoint.y)
                ),
                startPoint: .init(
                    x: Double(gradient.startPoint.x),
                    y: Double(gradient.startPoint.y)
                ),
                stops: stops
            )
        )
    }

    init?(scrollPocketEdge edge: UIRectEdge) {
        let startPoint: SRShapeGradientPoint
        let endPoint: SRShapeGradientPoint

        switch edge {
        case .top:
            startPoint = .init(x: 0.5, y: 0)
            endPoint = .init(x: 0.5, y: 1)
        case .bottom:
            startPoint = .init(x: 0.5, y: 1)
            endPoint = .init(x: 0.5, y: 0)
        default:
            return nil
        }

        self = .linear(
            value: .init(
                endPoint: endPoint,
                startPoint: startPoint,
                stops: [
                    .init(color: "#000000FF", position: 0),
                    .init(color: "#000000FF", position: 0.35),
                    .init(color: "#00000000", position: 1)
                ]
            )
        )
    }
}

extension String {
    static let fallbackColor = "#FF0000FF"
    fileprivate static let fallbackFontFamily = "-apple-system, BlinkMacSystemFont, 'Roboto', sans-serif"
}

extension CGFloat {
    fileprivate static let fallbackFontSize: Self = 10
}
#endif
