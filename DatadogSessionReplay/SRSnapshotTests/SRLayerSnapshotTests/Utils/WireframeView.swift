/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
@_spi(Internal)
@testable import DatadogSessionReplay

@available(iOS 13.0, *)
@MainActor
internal final class WireframeView: UIView {
    init?(
        _ wireframe: SRWireframe,
        identifiedResources: [String: Resource],
        parentFrame: CGRect
    ) {
        super.init(frame: wireframe.absoluteFrame.offsetBy(dx: -parentFrame.minX, dy: -parentFrame.minY))

        guard let contentView = makeContentView(
            for: wireframe,
            identifiedResources: identifiedResources
        ) else {
            return nil
        }

        backgroundColor = .clear
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeContentView(
        for wireframe: SRWireframe,
        identifiedResources: [String: Resource]
    ) -> UIView? {
        switch wireframe {
        case .shapeWireframe(let wireframe):
            return ShapeWireframeView(wireframe, frame: bounds)
        case .textWireframe(let wireframe):
            return TextWireframeView(wireframe, frame: bounds)
        case .imageWireframe(let wireframe):
            return ImageWireframeView(
                wireframe,
                identifiedResources: identifiedResources,
                frame: bounds
            )
        case .placeholderWireframe(let wireframe):
            return PlaceholderWireframeView(wireframe, frame: bounds)
        case .webviewWireframe(let wireframe):
            return WebViewWireframeView(wireframe, frame: bounds)
        case .embeddedContentWireframe(let wireframe):
            return EmbeddedContentWireframeView(wireframe, frame: bounds)
        }
    }
}

@available(iOS 13.0, *)
@MainActor
private final class ShapeWireframeView: UIView {
    private var backgroundGradientLayer: CAGradientLayer?

    init(_ wireframe: SRShapeWireframe, frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        applyWireframeShapeStyle(wireframe.shapeStyle, border: wireframe.border)

        if let backgroundGradient = wireframe.shapeStyle?.backgroundGradient {
            let gradientLayer = CAGradientLayer(backgroundGradient)
            gradientLayer.frame = bounds
            layer.insertSublayer(gradientLayer, at: 0)
            backgroundGradientLayer = gradientLayer
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundGradientLayer?.frame = bounds
    }
}

@available(iOS 13.0, *)
@MainActor
private final class TextWireframeView: UILabel {
    private var insets: UIEdgeInsets = .zero
    private var verticalAlignment: SRTextPosition.Alignment.Vertical = .top

    init(_ wireframe: SRTextWireframe, frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        text = wireframe.text
        textColor = UIColor(hexString: wireframe.textStyle.color)
        font = UIFont.systemFont(ofSize: CGFloat(wireframe.textStyle.size))
        textAlignment = NSTextAlignment(wireframe.textPosition?.alignment?.horizontal)
        verticalAlignment = wireframe.textPosition?.alignment?.vertical ?? .top
        lineBreakMode = NSLineBreakMode(wireframe.textStyle.truncationMode)
        numberOfLines = wireframe.textStyle.truncationMode == nil ? 0 : 1
        insets = UIEdgeInsets(wireframe.textPosition?.padding)
        applyWireframeShapeStyle(wireframe.shapeStyle, border: wireframe.border)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawText(in rect: CGRect) {
        let insetRect = rect.inset(by: insets)
        let textRect = super.textRect(forBounds: insetRect, limitedToNumberOfLines: numberOfLines)
        let drawRect: CGRect

        switch verticalAlignment {
        case .top:
            drawRect = CGRect(origin: insetRect.origin, size: textRect.size)
        case .center:
            drawRect = CGRect(
                x: insetRect.minX,
                y: insetRect.minY + (insetRect.height - textRect.height) / 2,
                width: insetRect.width,
                height: textRect.height
            )
        case .bottom:
            drawRect = CGRect(
                x: insetRect.minX,
                y: insetRect.maxY - textRect.height,
                width: insetRect.width,
                height: textRect.height
            )
        }

        super.drawText(in: drawRect)
    }
}

@available(iOS 13.0, *)
@MainActor
private final class ImageWireframeView: UIImageView {
    init(
        _ wireframe: SRImageWireframe,
        identifiedResources: [String: Resource],
        frame: CGRect
    ) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .scaleToFill
        image = wireframe.image(identifiedResources: identifiedResources)
        applyWireframeShapeStyle(wireframe.shapeStyle, border: wireframe.border)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 13.0, *)
@MainActor
private final class PlaceholderWireframeView: UIView {
    init(_ wireframe: SRPlaceholderWireframe, frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        applyWireframeShapeStyle(
            SRShapeStyle(backgroundColor: "#A9A9A9FF", cornerRadius: 0, opacity: 1),
            border: SRShapeBorder(color: "#000000FF", width: 4)
        )

        let label = UILabel(frame: bounds.insetBy(dx: 4, dy: 4))
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.text = wireframe.label ?? "Placeholder"
        label.textAlignment = .center
        label.textColor = .black
        label.font = .systemFont(ofSize: 24)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.4
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 13.0, *)
@MainActor
private final class WebViewWireframeView: UIView {
    init?(_ wireframe: SRWebviewWireframe, frame: CGRect) {
        guard wireframe.isVisible != false else {
            return nil
        }

        super.init(frame: frame)
        backgroundColor = .clear
        applyWireframeShapeStyle(wireframe.shapeStyle, border: wireframe.border)

        let label = UILabel(frame: bounds)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.text = "WKWebView"
        label.textAlignment = .center
        label.textColor = .black
        label.font = .systemFont(ofSize: 24)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 13.0, *)
@MainActor
private final class EmbeddedContentWireframeView: UIView {
    init?(_ wireframe: SREmbeddedContentWireframe, frame: CGRect) {
        guard wireframe.isVisible != false else {
            return nil
        }

        super.init(frame: frame)
        backgroundColor = .clear
        applyWireframeShapeStyle(wireframe.shapeStyle, border: wireframe.border)

        let label = UILabel(frame: bounds)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.text = "Embedded Content"
        label.textAlignment = .center
        label.textColor = .black
        label.font = .systemFont(ofSize: 24)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 13.0, *)
private extension SRWireframe {
    var absoluteFrame: CGRect {
        switch self {
        case .shapeWireframe(let value): value.absoluteFrame
        case .textWireframe(let value): value.absoluteFrame
        case .imageWireframe(let value): value.absoluteFrame
        case .placeholderWireframe(let value): value.absoluteFrame
        case .webviewWireframe(let value): value.absoluteFrame
        case .embeddedContentWireframe(let value): value.absoluteFrame
        }
    }
}

@available(iOS 13.0, *)
private extension SRShapeWireframe {
    var absoluteFrame: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
}

@available(iOS 13.0, *)
private extension SRTextWireframe {
    var absoluteFrame: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
}

@available(iOS 13.0, *)
private extension SRImageWireframe {
    var absoluteFrame: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    func image(identifiedResources: [String: Resource]) -> UIImage? {
        if let base64, let data = Data(base64Encoded: base64) {
            return UIImage(data: data, scale: UIScreen.main.scale)
        }

        guard let resourceId, let resource = identifiedResources[resourceId] else {
            return nil
        }

        let data = resource.calculateData()
        switch mimeType ?? resource.mimeType {
        case "image/svg+xml":
            return UIImage(svgData: data, scale: UIScreen.main.scale)
        default:
            return UIImage(data: data, scale: UIScreen.main.scale)
        }
    }
}

@available(iOS 13.0, *)
private extension SRPlaceholderWireframe {
    var absoluteFrame: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
}

@available(iOS 13.0, *)
private extension SRWebviewWireframe {
    var absoluteFrame: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
}

@available(iOS 13.0, *)
private extension SREmbeddedContentWireframe {
    var absoluteFrame: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
}

@available(iOS 13.0, *)
@MainActor
private extension UIView {
    func applyWireframeShapeStyle(_ shapeStyle: SRShapeStyle?, border: SRShapeBorder?) {
        if let backgroundColor = shapeStyle?.backgroundColor {
            self.backgroundColor = UIColor(hexString: backgroundColor)
        }
        if let cornerRadius = shapeStyle?.cornerRadius {
            layer.cornerRadius = CGFloat(cornerRadius)
            layer.masksToBounds = true
        }
        if let border {
            layer.borderColor = UIColor(hexString: border.color).cgColor
            layer.borderWidth = CGFloat(border.width)
        }
    }
}

private extension UIEdgeInsets {
    init(_ padding: SRTextPosition.Padding?) {
        self.init(
            top: CGFloat(padding?.top ?? 0),
            left: CGFloat(padding?.left ?? 0),
            bottom: CGFloat(padding?.bottom ?? 0),
            right: CGFloat(padding?.right ?? 0)
        )
    }
}

private extension NSTextAlignment {
    init(_ horizontalAlignment: SRTextPosition.Alignment.Horizontal?) {
        switch horizontalAlignment {
        case .right:
            self = .right
        case .center:
            self = .center
        case .left, nil:
            self = .left
        }
    }
}

private extension NSLineBreakMode {
    init(_ truncationMode: SRTextStyle.TruncationMode?) {
        switch truncationMode {
        case .clip:
            self = .byClipping
        case .head:
            self = .byTruncatingHead
        case .tail:
            self = .byTruncatingTail
        case .middle:
            self = .byTruncatingMiddle
        case nil:
            self = .byWordWrapping
        }
    }
}

private extension CAGradientLayer {
    convenience init(_ gradient: SRShapeGradient) {
        self.init()

        switch gradient {
        case .linear(let gradient):
            type = .axial
            colors = gradient.stops.map { UIColor(hexString: $0.color).cgColor }
            locations = gradient.stops.map { NSNumber(value: $0.position) }
            startPoint = CGPoint(
                x: CGFloat(gradient.startPoint.x),
                y: CGFloat(gradient.startPoint.y)
            )
            endPoint = CGPoint(
                x: CGFloat(gradient.endPoint.x),
                y: CGFloat(gradient.endPoint.y)
            )
        }
    }
}
