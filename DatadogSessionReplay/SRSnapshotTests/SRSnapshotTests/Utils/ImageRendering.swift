/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Framer
@testable import DatadogSessionReplay

/// Renders application window into image.
internal func renderImage(for window: UIWindow) -> UIImage {
    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    return renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
}

/// Renders wireframes into image.
internal func renderImage(for wireframes: [SRWireframe]) -> UIImage {
    guard !wireframes.isEmpty else {
        return UIImage()
    }

    let frame = wireframes[0].toFrame()
    let canvas = FramerCanvas.create(size: CGSize(width: frame.width, height: frame.height))
    canvas.draw(
        blueprint: Blueprint(
            id: "snapshot",
            contents: wireframes.map { .frame($0.toFrame()) }
        )
    )
    return canvas.image
}

// MARK: - Wireframes Rendering with Framer

private extension SRWireframe {
    func toFrame() -> BlueprintFrame {
        switch self {
        case .shapeWireframe(let shape):
            return shape.toFrame()
        case .textWireframe(let text):
            return text.toFrame()
        case .imageWireframe(value: let image):
            return image.toFrame()
        }
    }
}

private extension SRShapeWireframe {
    func toFrame() -> BlueprintFrame {
        BlueprintFrame(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height),
            style: frameStyle(border: border, style: shapeStyle),
            content: nil
        )
    }
}

private extension SRTextWireframe {
    func toFrame() -> BlueprintFrame {
        BlueprintFrame(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height),
            style: frameStyle(border: border, style: shapeStyle),
            content: frameContent(text: text, textStyle: textStyle, textPosition: textPosition)
        )
    }
}

private extension SRImageWireframe {
    func toFrame() -> BlueprintFrame {
        BlueprintFrame(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height),
            style: frameStyle(border: border, style: shapeStyle),
            content: frameContent(base64ImageString: base64)
        )
    }
}

private func frameStyle(border: SRShapeBorder?, style: SRShapeStyle?) -> BlueprintFrame.Style {
    var fs = BlueprintFrame.Style(
        lineWidth: 0,
        lineColor: .clear,
        fillColor: .clear,
        cornerRadius: 0,
        opacity: 1
    )

    if let border = border {
        fs.lineWidth = CGFloat(border.width)
        fs.lineColor = UIColor(hexString: border.color)
    }

    if let style = style {
        fs.fillColor = style.backgroundColor.flatMap { UIColor(hexString: $0) } ?? fs.fillColor
        fs.cornerRadius = style.cornerRadius.flatMap { CGFloat($0) } ?? fs.cornerRadius
        fs.opacity = style.opacity.flatMap { CGFloat($0) } ?? fs.opacity
    }

    return fs
}

private func frameContent(text: String, textStyle: SRTextStyle?, textPosition: SRTextPosition?) -> BlueprintFrame.Content {
    var horizontalAlignment: BlueprintFrame.Content.Alignment = .leading
    var verticalAlignment: BlueprintFrame.Content.Alignment = .leading

    if let textPosition = textPosition {
        switch textPosition.alignment?.horizontal {
        case .left?:    horizontalAlignment = .leading
        case .center?:  horizontalAlignment = .center
        case .right?:   horizontalAlignment = .trailing
        default:        break
        }
        switch textPosition.alignment?.vertical {
        case .top?:     verticalAlignment = .leading
        case .center?:  verticalAlignment = .center
        case .bottom?:  verticalAlignment = .trailing
        default:        break
        }
    }

    let contentType: BlueprintFrame.Content.ContentType
    if let textStyle = textStyle {
        contentType = .text(
            text: text,
            color: UIColor(hexString: textStyle.color),
            font: .systemFont(ofSize: CGFloat(textStyle.size))
        )
    } else {
        contentType = .text(text: text, color: .clear, font: .systemFont(ofSize: 8))
    }

    return .init(
        contentType: contentType,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: verticalAlignment
    )
}

private func frameContent(base64ImageString: String?) -> BlueprintFrame.Content {
    let base64Data = base64ImageString?.data(using: .utf8) ?? Data()
    let imageData = Data(base64Encoded: base64Data) ?? Data()
    let image = UIImage(data: imageData, scale: UIScreen.main.scale) ?? UIImage()
    let contentType: BlueprintFrame.Content.ContentType = .image(image: image)
    return .init(contentType: contentType)
}

private extension UIColor {
    convenience init(hexString: String) {
        precondition(hexString.count == 9, "Invalid `hexString` - expected 9 characters, got '\(hexString)'")
        precondition(hexString.hasPrefix("#"), "Invalid `hexString` - expected # prefix, got '\(hexString)'")

        guard let hex8 = UInt64(hexString.dropFirst(), radix: 16) else {
            preconditionFailure("Invalid `hexString`` - expected hexadecimal value, got '\(hexString)'")
        }

        let mask: UInt64 = 0x00000000FF
        self.init(
            red: CGFloat((hex8 >> 24) & mask) / CGFloat(255),
            green: CGFloat((hex8 >> 16) & mask) / CGFloat(255),
            blue: CGFloat((hex8 >> 8) & mask) / CGFloat(255),
            alpha: CGFloat(hex8  & mask) / CGFloat(255)
        )
    }
}
