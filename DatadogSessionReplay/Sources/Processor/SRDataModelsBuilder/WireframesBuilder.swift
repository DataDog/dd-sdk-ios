/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import CoreGraphics
import UIKit

@_spi(Internal)
public typealias WireframeID = NodeID

/// Builds the actual wireframes from VTS snapshots (produced by `Recorder`) to be later transported in SR
/// records (see `RecordsBuilder`) within SR segments (see `SegmentBuilder`).
/// A wireframe stands for semantic definition of an UI element (i.a.: label, button, tab bar).
/// It is used by the player to reconstruct individual elements of the recorded app UI.
///
/// Note: `WireframesBuilder` is used by `Processor` on a single background thread.
@_spi(Internal)
public class SessionReplayWireframesBuilder {
    /// A set of fallback values to use if the actual value cannot be read or converted.
    ///
    /// The idea is to always provide value, which would make certain element visible in the player.
    /// This should create faster feedback loop than if skipping inconsistent wireframes.
    struct Fallback {
        /// The color (solid red) to use when the actual color conversion goes wrong.
        static let color = "#FF0000FF"
        /// The font family to use when the actual one cannot be read.
        ///
        /// REPLAY-1421: This definition will promote SF font when running player in Safari, then “BlinkMacSystemFont” in macOS Chrome and
        /// will ultimately fallback to “Roboto” or any “sans-serif” in other web browsers.
        static let fontFamily = "-apple-system, BlinkMacSystemFont, 'Roboto', sans-serif"
        /// The font size to use when the actual one cannot be read.
        static let fontSize: CGFloat = 10
    }

    public struct FontOverride {
        let size: CGFloat?

        public init(size: CGFloat?) {
            self.size = size
        }
    }

    public func createShapeWireframe(
        id: WireframeID,
        frame: CGRect,
        clip: SRContentClip? = nil,
        borderColor: CGColor? = nil,
        borderWidth: CGFloat? = nil,
        backgroundColor: CGColor? = nil,
        cornerRadius: CGFloat? = nil,
        opacity: CGFloat? = nil
    ) -> SRWireframe {
        let wireframe = SRShapeWireframe(
            border: createShapeBorder(borderColor: borderColor, borderWidth: borderWidth),
            clip: clip,
            height: Int64(withNoOverflow: frame.height),
            id: id,
            shapeStyle: createShapeStyle(backgroundColor: backgroundColor, cornerRadius: cornerRadius, opacity: opacity),
            width: Int64(withNoOverflow: frame.width),
            x: Int64(withNoOverflow: frame.minX),
            y: Int64(withNoOverflow: frame.minY)
        )

        return .shapeWireframe(value: wireframe)
    }

    public func createImageWireframe(
        resourceId: String,
        id: WireframeID,
        frame: CGRect,
        mimeType: String = "png",
        clip: SRContentClip? = nil,
        borderColor: CGColor? = nil,
        borderWidth: CGFloat? = nil,
        backgroundColor: CGColor? = nil,
        cornerRadius: CGFloat? = nil,
        opacity: CGFloat? = nil
    ) -> SRWireframe {
        let wireframe = SRImageWireframe(
            base64: nil, // field deprecated - we should use resource endpoint instead
            border: createShapeBorder(borderColor: borderColor, borderWidth: borderWidth),
            clip: clip,
            height: Int64(withNoOverflow: frame.height),
            id: id,
            isEmpty: false, // field deprecated - we should use placeholder wireframe instead
            mimeType: mimeType,
            resourceId: resourceId,
            shapeStyle: createShapeStyle(backgroundColor: backgroundColor, cornerRadius: cornerRadius, opacity: opacity),
            width: Int64(withNoOverflow: frame.width),
            x: Int64(withNoOverflow: frame.minX),
            y: Int64(withNoOverflow: frame.minY)
        )
        return .imageWireframe(value: wireframe)
    }

    public func createTextWireframe(
        id: WireframeID,
        frame: CGRect,
        text: String,
        textFrame: CGRect? = nil,
        textAlignment: SRTextPosition.Alignment? = nil,
        clip: SRContentClip? = nil,
        textColor: CGColor? = nil,
        font: UIFont? = nil,
        fontOverride: FontOverride? = nil,
        fontScalingEnabled: Bool = false,
        borderColor: CGColor? = nil,
        borderWidth: CGFloat? = nil,
        backgroundColor: CGColor? = nil,
        cornerRadius: CGFloat? = nil,
        opacity: CGFloat? = nil
    ) -> SRWireframe {
        let textFrame = textFrame ?? frame
        let textPosition = SRTextPosition(
            alignment: textAlignment,
            padding: .init(
                bottom: Int64(withNoOverflow: frame.maxY - textFrame.maxY),
                left: Int64(withNoOverflow: textFrame.minX - frame.minX),
                right: Int64(withNoOverflow: frame.maxX - textFrame.maxX),
                top: Int64(withNoOverflow: textFrame.minY - frame.minY)
            )
        )

        var fontSize = Int64(withNoOverflow: fontOverride?.size ?? font?.pointSize ?? Fallback.fontSize)
        if text.count > 0, fontScalingEnabled {
            // Calculates the approximate font size for available text area √(frameArea / numberOfCharacters)
            let area = textFrame.width * textFrame.height
            let calculatedFontSize = Int64(sqrt(area / CGFloat(text.count)))
            if calculatedFontSize < fontSize {
                fontSize = calculatedFontSize
            }
        }

        // TODO: RUMM-2452 Better recognize the font:
        let textStyle = SRTextStyle(
            color: textColor.flatMap { hexString(from: $0) } ?? Fallback.color,
            family: Fallback.fontFamily,
            size: fontSize
        )

        let wireframe = SRTextWireframe(
            border: createShapeBorder(borderColor: borderColor, borderWidth: borderWidth),
            clip: clip,
            height: Int64(withNoOverflow: frame.height),
            id: id,
            shapeStyle: createShapeStyle(backgroundColor: backgroundColor, cornerRadius: cornerRadius, opacity: opacity),
            text: text,
            textPosition: textPosition,
            textStyle: textStyle,
            width: Int64(withNoOverflow: frame.width),
            x: Int64(withNoOverflow: frame.minX),
            y: Int64(withNoOverflow: frame.minY)
        )

        return .textWireframe(value: wireframe)
    }

    public func createPlaceholderWireframe(
        id: Int64,
        frame: CGRect,
        label: String,
        clip: SRContentClip? = nil
    ) -> SRWireframe {
        let wireframe = SRPlaceholderWireframe(
            clip: clip,
            height: Int64(withNoOverflow: frame.size.height),
            id: id,
            label: label,
            width: Int64(withNoOverflow: frame.size.width),
            x: Int64(withNoOverflow: frame.minX),
            y: Int64(withNoOverflow: frame.minY)
        )
        return .placeholderWireframe(value: wireframe)
    }

    public func createWebViewWireframe(
        id: Int64,
        frame: CGRect,
        slotId: String,
        clip: SRContentClip? = nil,
        borderColor: CGColor? = nil,
        borderWidth: CGFloat? = nil,
        backgroundColor: CGColor? = nil,
        cornerRadius: CGFloat? = nil,
        opacity: CGFloat? = nil
    ) -> SRWireframe {
        let wireframe = SRWebviewWireframe(
            border: createShapeBorder(borderColor: borderColor, borderWidth: borderWidth),
            clip: clip,
            height: Int64(withNoOverflow: frame.height),
            id: id,
            shapeStyle: createShapeStyle(backgroundColor: backgroundColor, cornerRadius: cornerRadius, opacity: opacity),
            slotId: slotId,
            width: Int64(withNoOverflow: frame.size.width),
            x: Int64(withNoOverflow: frame.minX),
            y: Int64(withNoOverflow: frame.minY)
        )

        return .webviewWireframe(value: wireframe)
    }

    // MARK: - Private

    private func createShapeBorder(borderColor: CGColor?, borderWidth: CGFloat?) -> SRShapeBorder? {
        guard let borderColor = borderColor, let borderWidth = borderWidth, borderWidth > 0.0 else {
            return nil
        }

        return .init(
            color: hexString(from: borderColor) ?? Fallback.color,
            width: Int64(withNoOverflow: borderWidth.rounded(.up))
        )
    }

    private func createShapeStyle(backgroundColor: CGColor?, cornerRadius: CGFloat?, opacity: CGFloat?) -> SRShapeStyle? {
        guard let backgroundColor = backgroundColor else {
            return nil
        }

        return .init(
            backgroundColor: hexString(from: backgroundColor) ?? Fallback.color,
            cornerRadius: cornerRadius.map { Double($0) },
            opacity: opacity.map { Double($0) }
        )
    }
}

// This alias enables us to have a more unique name exposed through public-internal access level
internal typealias WireframesBuilder = SessionReplayWireframesBuilder

// MARK: - Convenience

internal extension WireframesBuilder {
    func createShapeWireframe(id: WireframeID, frame: CGRect, attributes: ViewAttributes) -> SRWireframe {
        return createShapeWireframe(
            id: id,
            frame: frame,
            clip: nil,
            borderColor: attributes.layerBorderColor,
            borderWidth: attributes.layerBorderWidth,
            backgroundColor: attributes.backgroundColor,
            cornerRadius: attributes.layerCornerRadius,
            opacity: attributes.alpha
        )
    }
}

extension SRContentClip {
    /// This method is a convenience for exposing the internal default init.
    @_spi(Internal)
    public static func create(
        bottom: Int64?,
        left: Int64?,
        right: Int64?,
        top: Int64?
    ) -> SRContentClip {
        return SRContentClip(
            bottom: bottom,
            left: left,
            right: right,
            top: top
        )
    }
}
#endif
