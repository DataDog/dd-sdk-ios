/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CoreGraphics
import UIKit

internal typealias WireframeID = NodeID

/// Builds the actual wireframes from VTS snapshots (produced by `Recorder`) to be later transported in SR
/// records (see `RecordsBuilder`) within SR segments (see `SegmentBuilder`).
/// A wireframe stands for semantic definition of an UI element (i.a.: label, button, tab bar).
/// It is used by the player to reconstruct individual elements of the recorded app UI.
///
/// Note: `WireframesBuilder` is used by `Processor` on a single background thread.
internal class WireframesBuilder {
    /// A set of fallback values to use if the actual value cannot be read or converted.
    ///
    /// The idea is to always provide value, which would make certain element visible in the player.
    /// This should create faster feedback loop than if skipping inconsistent wireframes.
    struct Fallback {
        /// The color (solid red) to use when the actual color conversion goes wrong.
        static let color = "#FF0000FF"
        /// The font family to use when the actual one cannot be read.
        static let fontFamily = "-apple-system, Roboto, Helvetica, Arial"
        /// The font size to use when the actual one cannot be read.
        static let fontSize: CGFloat = 10
    }

    func createShapeWireframe(
        id: WireframeID,
        frame: CGRect,
        borderColor: CGColor? = nil,
        borderWidth: CGFloat? = nil,
        backgroundColor: CGColor? = nil,
        cornerRadius: CGFloat? = nil,
        opacity: CGFloat? = nil
    ) -> SRWireframe {
        let wireframe = SRShapeWireframe(
            border: createShapeBorder(borderColor: borderColor, borderWidth: borderWidth),
            height: Int64(withNoOverflow: frame.height),
            id: id,
            shapeStyle: createShapeStyle(backgroundColor: backgroundColor, cornerRadius: cornerRadius, opacity: opacity),
            width: Int64(withNoOverflow: frame.width),
            x: Int64(withNoOverflow: frame.minX),
            y: Int64(withNoOverflow: frame.minY)
        )

        return .shapeWireframe(value: wireframe)
    }

    func createTextWireframe(
        id: WireframeID,
        frame: CGRect,
        text: String,
        textFrame: CGRect? = nil,
        textColor: CGColor? = nil,
        font: UIFont? = nil,
        borderColor: CGColor? = nil,
        borderWidth: CGFloat? = nil,
        backgroundColor: CGColor? = nil,
        cornerRadius: CGFloat? = nil,
        opacity: CGFloat? = nil
    ) -> SRWireframe {
        var textPosition: SRTextPosition? = nil

        if let textFrame = textFrame {
            textPosition = .init(
                alignment: nil, // TODO: RUMM-2452 Improve text rendering
                padding: .init(
                    bottom: Int64(withNoOverflow: frame.maxY - textFrame.maxY),
                    left: Int64(withNoOverflow: textFrame.minX - frame.minX),
                    right: Int64(withNoOverflow: frame.maxX - textFrame.maxX),
                    top: Int64(withNoOverflow: textFrame.minY - frame.minY)
                )
            )
        }

        // TODO: RUMM-2452 Better recognize the font:
        let textStyle = SRTextStyle(
            color: textColor.flatMap { hexString(from: $0) } ?? Fallback.color,
            family: Fallback.fontFamily,
            size: Int64(withNoOverflow: font?.pointSize ?? Fallback.fontSize)
        )

        let wireframe = SRTextWireframe(
            border: createShapeBorder(borderColor: borderColor, borderWidth: borderWidth),
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
