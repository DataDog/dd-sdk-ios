/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

/// The border properties of this wireframe. The default value is null (no-border).
@_spi(Internal) public struct ShapeBorder {
    /// The border color as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
    public let color: String

    /// The width of the border in pixels.
    public let width: Int64

    internal func toSRShapeBorder() -> SRShapeBorder {
        return .init(color: color, width: width)
    }
}

/// Schema of clipping information for a Wireframe.
@_spi(Internal) public struct ContentClip {
    /// The amount of space in pixels that needs to be clipped (masked) at the bottom of the wireframe.
    public let bottom: Int64?

    /// The amount of space in pixels that needs to be clipped (masked) at the left of the wireframe.
    public let left: Int64?

    /// The amount of space in pixels that needs to be clipped (masked) at the right of the wireframe.
    public let right: Int64?

    /// The amount of space in pixels that needs to be clipped (masked) at the top of the wireframe.
    public let top: Int64?

    public init(bottom: Int64?, left: Int64?, right: Int64?, top: Int64?) {
        self.bottom = bottom
        self.left = left
        self.right = right
        self.top = top
    }

    internal func toSRContentClip() -> SRContentClip {
        return .init(bottom: bottom, left: left, right: right, top: top)
    }
}

/// The style of this wireframe.
@_spi(Internal) public struct ShapeStyle {
    /// The background color for this wireframe as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional. The default value is #FFFFFF00.
    public let backgroundColor: String?

    /// The corner(border) radius of this wireframe in pixels. The default value is 0.
    public let cornerRadius: Double?

    /// The opacity of this wireframe. Takes values from 0 to 1, default value is 1.
    public let opacity: Double?

    internal func toSRShapeStyle() -> SRShapeStyle {
        return .init(
            backgroundColor: backgroundColor,
            cornerRadius: cornerRadius,
            opacity: opacity
        )
    }
}

/// Schema of all properties of a ShapeWireframe.
@_spi(Internal) public struct ShapeWireframe {
    /// The border properties of this wireframe. The default value is null (no-border).
    public let border: ShapeBorder?

    /// Schema of clipping information for a Wireframe.
    public let clip: ContentClip?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    public let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    public let id: Int64

    /// The style of this wireframe.
    public let shapeStyle: ShapeStyle?

    /// The type of the wireframe.
    public let type: String = "shape"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    public let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let y: Int64

    internal func toSRShapeWireframe() -> SRShapeWireframe {
        return SRShapeWireframe(
            border: border?.toSRShapeBorder(),
            clip: clip?.toSRContentClip(),
            height: height,
            id: id,
            shapeStyle: shapeStyle?.toSRShapeStyle(),
            width: width,
            x: x,
            y: y
        )
    }
}

/// Schema of all properties of a TextPosition.
@_spi(Internal) public struct TextPosition {
    public let alignment: Alignment?

    public let padding: Padding?

    public struct Alignment {
        /// The horizontal text alignment. The default value is `left`.
        public let horizontal: Horizontal?

        /// The vertical text alignment. The default value is `top`.
        public let vertical: Vertical?

        /// The horizontal text alignment. The default value is `left`.
        public enum Horizontal: String, Codable {
            case left = "left"
            case right = "right"
            case center = "center"
        }

        /// The vertical text alignment. The default value is `top`.
        public enum Vertical: String, Codable {
            case top = "top"
            case bottom = "bottom"
            case center = "center"
        }

        public init(horizontal: Horizontal?, vertical: Vertical?) {
            self.horizontal = horizontal
            self.vertical = vertical
        }

        internal func toSRAlignment() -> SRTextPosition.Alignment? {
            if let verticalValue = vertical?.rawValue as? String {
                if let horizontalValue = horizontal?.rawValue as? String {
                    return .init(
                        horizontal: .init(rawValue: horizontalValue),
                        vertical: .init(rawValue: verticalValue)
                    )
                }

                return .init(horizontal: nil, vertical: .init(rawValue: verticalValue))
            }

            if let horizontalValue = horizontal?.rawValue as? String {
                return .init(horizontal: .init(rawValue: horizontalValue), vertical: nil)
            }

            return .init(horizontal: nil, vertical: nil)
        }
    }

    public struct Padding: Codable, Hashable {
        /// The bottom padding in pixels. The default value is 0.
        public let bottom: Int64?

        /// The left padding in pixels. The default value is 0.
        public let left: Int64?

        /// The right padding in pixels. The default value is 0.
        public let right: Int64?

        /// The top padding in pixels. The default value is 0.
        public let top: Int64?
    }

    internal func toSRTextPosition() -> SRTextPosition {
        return .init(
            alignment: alignment?.toSRAlignment(),
            padding: .init(
                bottom: padding?.bottom,
                left: padding?.left,
                right: padding?.right,
                top: padding?.top
            )
        )
    }
}

/// Schema of all properties of a TextStyle.
@_spi(Internal) public struct TextStyle {
    /// The font color as a string hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
    public let color: String

    /// The preferred font family collection, ordered by preference and formatted as a String list: e.g. Century Gothic, Verdana, sans-serif
    public let family: String

    /// The font size in pixels.
    public let size: Int64

    internal func toSRTextStyle() -> SRTextStyle {
        return .init(color: color, family: family, size: size)
    }
}

/// Schema of all properties of a TextWireframe.
@_spi(Internal) public struct TextWireframe {
    /// The border properties of this wireframe. The default value is null (no-border).
    public let border: ShapeBorder?

    /// Schema of clipping information for a Wireframe.
    public let clip: ContentClip?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    public let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    public let id: Int64

    /// The style of this wireframe.
    public let shapeStyle: ShapeStyle?

    /// The text value of the wireframe.
    public var text: String

    /// Schema of all properties of a TextPosition.
    public let textPosition: TextPosition?

    /// Schema of all properties of a TextStyle.
    public let textStyle: TextStyle

    /// The type of the wireframe.
    public let type: String = "text"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    public let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let y: Int64

    internal func toSRTextWireframe() -> SRTextWireframe {
        return SRTextWireframe(
            border: border?.toSRShapeBorder(),
            clip: clip?.toSRContentClip(),
            height: height,
            id: id,
            shapeStyle: shapeStyle?.toSRShapeStyle(),
            text: text,
            textPosition: textPosition?.toSRTextPosition(),
            textStyle: textStyle.toSRTextStyle(),
            width: width,
            x: x,
            y: y
        )
    }
}

/// Schema of all properties of a ImageWireframe.
@_spi(Internal) public struct ImageWireframe {
    /// base64 representation of the image. Not required as the ImageWireframe can be initialised without any base64
    public var base64: String?

    /// The border properties of this wireframe. The default value is null (no-border).
    public let border: ShapeBorder?

    /// Schema of clipping information for a Wireframe.
    public let clip: ContentClip?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    public let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    public let id: Int64

    /// Flag describing an image wireframe that should render an empty state placeholder
    public var isEmpty: Bool?

    /// MIME type of the image file
    public var mimeType: String?

    /// Unique identifier of the image resource
    public var resourceId: String?

    /// The style of this wireframe.
    public let shapeStyle: ShapeStyle?

    /// The type of the wireframe.
    public let type: String = "image"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    public let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let y: Int64

    internal func toSRImageWireframe() -> SRImageWireframe {
        return SRImageWireframe(
            base64: base64,
            border: border?.toSRShapeBorder(),
            clip: clip?.toSRContentClip(),
            height: height,
            id: id,
            isEmpty: isEmpty,
            mimeType: mimeType,
            resourceId: resourceId,
            shapeStyle: shapeStyle?.toSRShapeStyle(),
            width: width,
            x: x,
            y: y
        )
    }
}

/// Schema of all properties of a PlaceholderWireframe.
@_spi(Internal) public struct PlaceholderWireframe {
    /// Schema of clipping information for a Wireframe.
    public let clip: ContentClip?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    public let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    public let id: Int64

    /// Label of the placeholder
    public var label: String?

    /// The type of the wireframe.
    public let type: String = "placeholder"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    public let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let y: Int64

    internal func toSRPlaceholderWireframe() -> SRPlaceholderWireframe {
        return SRPlaceholderWireframe(
            clip: clip?.toSRContentClip(),
            height: height,
            id: id,
            label: label,
            width: width,
            x: x,
            y: y
        )
    }
}

/// Schema of a Wireframe type.
@_spi(Internal) public enum Wireframe {
    case shapeWireframe(value: ShapeWireframe)
    case textWireframe(value: TextWireframe)
    case imageWireframe(value: ImageWireframe)
    case placeholderWireframe(value: PlaceholderWireframe)

    internal func toSRWireframe() -> SRWireframe {
        switch self {
        case .shapeWireframe(let value):
            return .shapeWireframe(value: value.toSRShapeWireframe())
        case .textWireframe(let value):
            return .textWireframe(value: value.toSRTextWireframe())
        case .imageWireframe(let value):
            return .imageWireframe(value: value.toSRImageWireframe())
        case .placeholderWireframe(let value):
            return .placeholderWireframe(value: value.toSRPlaceholderWireframe())
        }
    }
}

extension TextPosition.Alignment {
    /// Custom initializer that allows transforming UIKit's `NSTextAlignment` into `SRTextPosition.Alignment`.
    public init(
        systemTextAlignment: NSTextAlignment,
        vertical: TextPosition.Alignment.Vertical = .center
    ) {
        self.vertical = vertical
        switch systemTextAlignment {
        case .left:
            self.horizontal = .left
        case .center:
            self.horizontal = .center
        case .right:
            self.horizontal = .right
        case .justified:
            self.horizontal = .left
        case .natural:
            self.horizontal = .left
        @unknown default:
            self.horizontal = .left
        }
    }
}
#endif
