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
    /// The resources that were collected while processing snapshots.
    private(set) var resources: [Resource]
    /// The cache of webview slot IDs in memory during snapshot.
    private var webViewSlotIDs: Set<Int>

    /// Creates a builder for builder wireframes in snapshot processing.
    ///
    /// The builder takes optional webview slot IDs in cache that can be updated
    /// while traversing the node. The cache will be used to create wireframes
    /// that are not visible be still need to be kept by the player.
    ///
    /// - Parameter webviewSlotIDs: The webview slot IDs in memory during snapshot.
    init(resources: [Resource] = [], webViewSlotIDs: Set<Int> = []) {
        self.resources = resources
        self.webViewSlotIDs = webViewSlotIDs
    }
}

@_spi(Internal)
extension SessionReplayWireframesBuilder {
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
        clip: CGRect,
        borderColor: CGColor? = nil,
        borderWidth: CGFloat? = nil,
        backgroundColor: CGColor? = nil,
        cornerRadius: CGFloat? = nil,
        opacity: CGFloat? = nil
    ) -> SRWireframe {
        let wireframe = SRShapeWireframe(
            border: createShapeBorder(borderColor: borderColor, borderWidth: borderWidth),
            clip: SRContentClip(frame, intersecting: clip),
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
        id: WireframeID,
        resource: SessionReplayResource,
        frame: CGRect,
        clip: CGRect,
        borderColor: CGColor? = nil,
        borderWidth: CGFloat? = nil,
        backgroundColor: CGColor? = nil,
        cornerRadius: CGFloat? = nil,
        opacity: CGFloat? = nil
    ) -> SRWireframe {
        // Save resource
        resources.append(resource)

        let wireframe = SRImageWireframe(
            base64: nil, // field deprecated - we should use resource endpoint instead
            border: createShapeBorder(borderColor: borderColor, borderWidth: borderWidth),
            clip: SRContentClip(frame, intersecting: clip),
            height: Int64(withNoOverflow: frame.height),
            id: id,
            isEmpty: false, // field deprecated - we should use placeholder wireframe instead
            mimeType: resource.mimeType,
            resourceId: resource.calculateIdentifier(),
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
        clip: CGRect,
        text: String,
        textFrame: CGRect? = nil,
        textAlignment: SRTextPosition.Alignment? = nil,
        textColor: CGColor? = nil,
        font: UIFont? = nil,
        fontOverride: FontOverride? = nil,
        fontScalingEnabled: Bool = false,
        truncationMode: SRTextStyle.TruncationMode? = nil,
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
            size: fontSize,
            truncationMode: truncationMode
        )

        let wireframe = SRTextWireframe(
            border: createShapeBorder(borderColor: borderColor, borderWidth: borderWidth),
            clip: SRContentClip(frame, intersecting: clip),
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
        clip: CGRect,
        label: String
    ) -> SRWireframe {
        let wireframe = SRPlaceholderWireframe(
            clip: SRContentClip(frame, intersecting: clip),
            height: Int64(withNoOverflow: frame.size.height),
            id: id,
            label: label,
            width: Int64(withNoOverflow: frame.size.width),
            x: Int64(withNoOverflow: frame.minX),
            y: Int64(withNoOverflow: frame.minY)
        )
        return .placeholderWireframe(value: wireframe)
    }

    public func visibleWebViewWireframe(
        id: Int,
        frame: CGRect,
        clip: CGRect,
        borderColor: CGColor? = nil,
        borderWidth: CGFloat? = nil,
        backgroundColor: CGColor? = nil,
        cornerRadius: CGFloat? = nil,
        opacity: CGFloat? = nil
    ) -> SRWireframe {
        let wireframe = SRWebviewWireframe(
            border: createShapeBorder(borderColor: borderColor, borderWidth: borderWidth),
            clip: SRContentClip(frame, intersecting: clip),
            height: Int64(withNoOverflow: frame.height),
            id: Int64(id),
            isVisible: true,
            shapeStyle: createShapeStyle(backgroundColor: backgroundColor, cornerRadius: cornerRadius, opacity: opacity),
            slotId: String(id),
            width: Int64(withNoOverflow: frame.size.width),
            x: Int64(withNoOverflow: frame.minX),
            y: Int64(withNoOverflow: frame.minY)
        )

        /// Remove the slot from the builder because a wireframe
        /// has been created.
        webViewSlotIDs.remove(id)
        return .webviewWireframe(value: wireframe)
    }

    public func hiddenWebViewWireframes() -> [SRWireframe] {
        defer { webViewSlotIDs.removeAll() }
        return webViewSlotIDs.map { id in
            let wireframe = SRWebviewWireframe(
                border: nil,
                clip: nil,
                height: 0,
                id: Int64(id),
                isVisible: false,
                shapeStyle: nil,
                slotId: String(id),
                width: 0,
                x: 0,
                y: 0
            )

            return .webviewWireframe(value: wireframe)
        }
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

        return SRShapeStyle(
            backgroundColor: hexString(from: backgroundColor) ?? Fallback.color,
            cornerRadius: cornerRadius.flatMap { $0.isNaN ? nil : Double($0) },
            opacity: opacity.flatMap { $0.isNaN ? nil : Double($0) }
        )
    }
}

// This alias enables us to have a more unique name exposed through public-internal access level
internal typealias WireframesBuilder = SessionReplayWireframesBuilder

// MARK: - Convenience

internal extension WireframesBuilder {
    func createShapeWireframe(id: WireframeID, attributes: ViewAttributes) -> SRWireframe {
        return createShapeWireframe(
            id: id,
            frame: attributes.frame,
            clip: attributes.clip,
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

    /// Creates a Content Clip by intersecting the view frame with the clipping rectangle.
    ///
    /// The clipping rectangle usually represents the bounds of the parent view when `clipsToBounds` is enabled.
    /// It determines which portion of the view should remain visible after clipping.
    ///
    /// If the intersection is empty, the view is completely clipped, and the resulting clip dimensions reflect the view’s size,
    /// indicating no visible content. This will result in a wireframe with no drawing area, recorders should, in practice, prevent
    /// this use case.
    ///
    /// - Parameters:
    ///   - frame: The view frame.
    ///   - clip: The clipping rectangle representing the visible area.
    init?(_ frame: CGRect, intersecting clip: CGRect) {
        let intersection = frame.intersection(clip)

        guard !intersection.isEmpty else {
            self.init(
                bottom: nil,
                left: Int64(withNoOverflow: frame.width),
                right: nil,
                top: Int64(withNoOverflow: frame.height)
            )

            return
        }

        let top = intersection.minY - frame.minY
        let left = intersection.minX - frame.minX
        let bottom = frame.maxY - intersection.maxY
        let right = frame.maxX - intersection.maxX

        // more reliable than intersection == frame
        if top.isZero, left.isZero, bottom.isZero, right.isZero {
            return nil
        }

        self.init(
            bottom: bottom.isZero ? nil : Int64(withNoOverflow: bottom),
            left: left.isZero ? nil : Int64(withNoOverflow: left),
            right: right.isZero ? nil : Int64(withNoOverflow: right),
            top: top.isZero ? nil : Int64(withNoOverflow: top)
        )
    }
}

#endif
