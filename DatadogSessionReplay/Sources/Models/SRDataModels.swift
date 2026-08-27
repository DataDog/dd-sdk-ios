/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal

// This file was generated from JSON Schema. Do not modify it directly.

// swiftlint:disable all

internal protocol SRDataModel: Codable {}

/// A rendering group that groups child wireframes and child layers. Does not draw pixels itself. Ordered rendering modifiers and compositing are applied to its composed output.
@_spi(Internal)
public struct SRCompositionLayer: Codable, Hashable {
    /// Ordered back-to-front references to child wireframes or child layers.
    public let children: [SRCompositionLayerChild]

    /// Operation used when compositing the rendered group into its parent.
    public let compositeOperation: CompositeOperation?

    /// The height in pixels of the layer. Uses the same coordinate space as mobile wireframes.
    public let height: Int64

    /// Stable layer identifier, persistent throughout the view lifetime.
    public let id: Int64

    /// Ordered list of rendering modifiers applied to the composed layer output in array order.
    public let modifiers: [SRCompositionLayerModifier]?

    /// The width in pixels of the layer. Uses the same coordinate space as mobile wireframes.
    public let width: Int64

    /// The position in pixels on the X axis of the layer in absolute coordinates. Uses the same coordinate space as mobile wireframes.
    public let x: Int64

    /// The position in pixels on the Y axis of the layer in absolute coordinates. Uses the same coordinate space as mobile wireframes.
    public let y: Int64

    public enum CodingKeys: String, CodingKey {
        case children = "children"
        case compositeOperation = "compositeOperation"
        case height = "height"
        case id = "id"
        case modifiers = "modifiers"
        case width = "width"
        case x = "x"
        case y = "y"
    }

    /// A rendering group that groups child wireframes and child layers. Does not draw pixels itself. Ordered rendering modifiers and compositing are applied to its composed output.
    ///
    /// - Parameters:
    ///   - children: Ordered back-to-front references to child wireframes or child layers.
    ///   - compositeOperation: Operation used when compositing the rendered group into its parent.
    ///   - height: The height in pixels of the layer. Uses the same coordinate space as mobile wireframes.
    ///   - id: Stable layer identifier, persistent throughout the view lifetime.
    ///   - modifiers: Ordered list of rendering modifiers applied to the composed layer output in array order.
    ///   - width: The width in pixels of the layer. Uses the same coordinate space as mobile wireframes.
    ///   - x: The position in pixels on the X axis of the layer in absolute coordinates. Uses the same coordinate space as mobile wireframes.
    ///   - y: The position in pixels on the Y axis of the layer in absolute coordinates. Uses the same coordinate space as mobile wireframes.
    public init(
        children: [SRCompositionLayerChild],
        compositeOperation: CompositeOperation? = nil,
        height: Int64,
        id: Int64,
        modifiers: [SRCompositionLayerModifier]? = nil,
        width: Int64,
        x: Int64,
        y: Int64
    ) {
        self.children = children
        self.compositeOperation = compositeOperation
        self.height = height
        self.id = id
        self.modifiers = modifiers
        self.width = width
        self.x = x
        self.y = y
    }

    /// Operation used when compositing the rendered group into its parent.
    @_spi(Internal)
    public enum CompositeOperation: String, Codable {
        case sourceOver = "sourceOver"
        case destinationIn = "destinationIn"
        case destinationOut = "destinationOut"
        case plusDarker = "plusDarker"
    }
}

/// Adds a signed brightness bias to the rendered layer contents.
@_spi(Internal)
public struct SRCompositionLayerBrightnessBiasModifier: Codable, Hashable {
    /// The type of the modifier.
    public let type: String = "brightnessBias"

    /// Brightness bias from -1 to 1 added to each normalized RGB channel (alpha is unchanged). 0 leaves content unchanged. Positive values brighten; negative values darken. Each channel is clamped to [0, 1] after the bias is applied.
    public let value: Double

    public enum CodingKeys: String, CodingKey {
        case type = "type"
        case value = "value"
    }

    /// Adds a signed brightness bias to the rendered layer contents.
    ///
    /// - Parameters:
    ///   - value: Brightness bias from -1 to 1 added to each normalized RGB channel (alpha is unchanged). 0 leaves content unchanged. Positive values brighten; negative values darken. Each channel is clamped to [0, 1] after the bias is applied.
    public init(
        value: Double
    ) {
        self.value = value
    }
}

/// A reference to a child wireframe or child layer in a composition layer.
@_spi(Internal)
public struct SRCompositionLayerChild: Codable, Hashable {
    /// The id of the referenced wireframe or layer.
    public let id: Int64

    /// The type of the child reference.
    public let type: SRCompositionLayerChildType

    public enum CodingKeys: String, CodingKey {
        case id = "id"
        case type = "type"
    }

    /// A reference to a child wireframe or child layer in a composition layer.
    ///
    /// - Parameters:
    ///   - id: The id of the referenced wireframe or layer.
    ///   - type: The type of the child reference.
    public init(
        id: Int64,
        type: SRCompositionLayerChildType
    ) {
        self.id = id
        self.type = type
    }
}

/// The type of the child reference.
@_spi(Internal)
public enum SRCompositionLayerChildType: String, Codable {
    case wireframe = "wireframe"
    case layer = "layer"
}

/// Geometric clipping applied to the composed layer output, in coordinates local to the layer rectangle.
@_spi(Internal)
public struct SRCompositionLayerClipModifier: Codable, Hashable {
    /// Path fill rule. Defaults to 'nonzero'.
    public let fillRule: FillRule?

    /// SVG path string defining the clip region, in coordinates local to the layer rectangle.
    public let path: String

    /// The type of the modifier.
    public let type: String = "clip"

    public enum CodingKeys: String, CodingKey {
        case fillRule = "fillRule"
        case path = "path"
        case type = "type"
    }

    /// Geometric clipping applied to the composed layer output, in coordinates local to the layer rectangle.
    ///
    /// - Parameters:
    ///   - fillRule: Path fill rule. Defaults to 'nonzero'.
    ///   - path: SVG path string defining the clip region, in coordinates local to the layer rectangle.
    public init(
        fillRule: FillRule? = nil,
        path: String
    ) {
        self.fillRule = fillRule
        self.path = path
    }

    /// Path fill rule. Defaults to 'nonzero'.
    @_spi(Internal)
    public enum FillRule: String, Codable {
        case nonzero = "nonzero"
        case evenodd = "evenodd"
    }
}

/// Color transformation using a 4x5 matrix applied to the composed layer output.
@_spi(Internal)
public struct SRCompositionLayerColorMatrixModifier: Codable, Hashable {
    /// 4x5 color matrix encoded as 20 numbers in row-major order. Input and output color channels are normalized to [0, 1]. The transform for each output channel is: R' = m[0]*R + m[1]*G + m[2]*B + m[3]*A + m[4], G' = m[5]*R + m[6]*G + m[7]*B + m[8]*A + m[9], B' = m[10]*R + m[11]*G + m[12]*B + m[13]*A + m[14], A' = m[15]*R + m[16]*G + m[17]*B + m[18]*A + m[19]. Each output channel is clamped to [0, 1] after evaluation.
    public let matrix: [Double]

    /// The type of the modifier.
    public let type: String = "colorMatrix"

    public enum CodingKeys: String, CodingKey {
        case matrix = "matrix"
        case type = "type"
    }

    /// Color transformation using a 4x5 matrix applied to the composed layer output.
    ///
    /// - Parameters:
    ///   - matrix: 4x5 color matrix encoded as 20 numbers in row-major order. Input and output color channels are normalized to [0, 1]. The transform for each output channel is: R' = m[0]*R + m[1]*G + m[2]*B + m[3]*A + m[4], G' = m[5]*R + m[6]*G + m[7]*B + m[8]*A + m[9], B' = m[10]*R + m[11]*G + m[12]*B + m[13]*A + m[14], A' = m[15]*R + m[16]*G + m[17]*B + m[18]*A + m[19]. Each output channel is clamped to [0, 1] after evaluation.
    public init(
        matrix: [Double]
    ) {
        self.matrix = matrix
    }
}

/// Gaussian blur applied to the composed layer output.
@_spi(Internal)
public struct SRCompositionLayerGaussianBlurModifier: Codable, Hashable {
    /// Gaussian blur radius.
    public let radius: Double

    /// The type of the modifier.
    public let type: String = "gaussianBlur"

    public enum CodingKeys: String, CodingKey {
        case radius = "radius"
        case type = "type"
    }

    /// Gaussian blur applied to the composed layer output.
    ///
    /// - Parameters:
    ///   - radius: Gaussian blur radius.
    public init(
        radius: Double
    ) {
        self.radius = radius
    }
}

/// Image mask applied to the composed layer output at this point in the modifier order. The referenced image is mapped to the layer bounds and interpreted as an alpha mask: transparent pixels hide content, opaque pixels keep content, and partial alpha multiplies content alpha. RGB channels are ignored.
@_spi(Internal)
public struct SRCompositionLayerMaskImageModifier: Codable, Hashable {
    /// Unique identifier of the image resource used as a bounds-aligned alpha mask.
    public let resourceId: String

    /// The type of the modifier.
    public let type: String = "maskImage"

    public enum CodingKeys: String, CodingKey {
        case resourceId = "resourceId"
        case type = "type"
    }

    /// Image mask applied to the composed layer output at this point in the modifier order. The referenced image is mapped to the layer bounds and interpreted as an alpha mask: transparent pixels hide content, opaque pixels keep content, and partial alpha multiplies content alpha. RGB channels are ignored.
    ///
    /// - Parameters:
    ///   - resourceId: Unique identifier of the image resource used as a bounds-aligned alpha mask.
    public init(
        resourceId: String
    ) {
        self.resourceId = resourceId
    }
}

/// A rendering modifier applied to the composed layer output.
@_spi(Internal)
public enum SRCompositionLayerModifier: Codable, Hashable {
    case compositionLayerClipModifier(value: SRCompositionLayerClipModifier)
    case compositionLayerOpacityModifier(value: SRCompositionLayerOpacityModifier)
    case compositionLayerColorMatrixModifier(value: SRCompositionLayerColorMatrixModifier)
    case compositionLayerGaussianBlurModifier(value: SRCompositionLayerGaussianBlurModifier)
    case compositionLayerShadowModifier(value: SRCompositionLayerShadowModifier)
    case compositionLayerBrightnessBiasModifier(value: SRCompositionLayerBrightnessBiasModifier)
    case compositionLayerSaturateModifier(value: SRCompositionLayerSaturateModifier)
    case compositionLayerMaskImageModifier(value: SRCompositionLayerMaskImageModifier)

    private enum DiscriminatorCodingKeys: String, CodingKey {
        case discriminator = "type"
    }

    // MARK: - Codable

    public func encode(to encoder: Encoder) throws {
        // Encode only the associated value, without encoding enum case
        var container = encoder.singleValueContainer()

        switch self {
        case .compositionLayerClipModifier(let value):
            try container.encode(value)
        case .compositionLayerOpacityModifier(let value):
            try container.encode(value)
        case .compositionLayerColorMatrixModifier(let value):
            try container.encode(value)
        case .compositionLayerGaussianBlurModifier(let value):
            try container.encode(value)
        case .compositionLayerShadowModifier(let value):
            try container.encode(value)
        case .compositionLayerBrightnessBiasModifier(let value):
            try container.encode(value)
        case .compositionLayerSaturateModifier(let value):
            try container.encode(value)
        case .compositionLayerMaskImageModifier(let value):
            try container.encode(value)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode enum case from discriminator
        let container = try decoder.singleValueContainer()
        let discriminatorContainer = try decoder.container(keyedBy: DiscriminatorCodingKeys.self)

        switch try discriminatorContainer.decode(String.self, forKey: .discriminator) {
        case "clip":
            self = .compositionLayerClipModifier(value: try container.decode(SRCompositionLayerClipModifier.self))
            return
        case "opacity":
            self = .compositionLayerOpacityModifier(value: try container.decode(SRCompositionLayerOpacityModifier.self))
            return
        case "colorMatrix":
            self = .compositionLayerColorMatrixModifier(value: try container.decode(SRCompositionLayerColorMatrixModifier.self))
            return
        case "gaussianBlur":
            self = .compositionLayerGaussianBlurModifier(value: try container.decode(SRCompositionLayerGaussianBlurModifier.self))
            return
        case "shadow":
            self = .compositionLayerShadowModifier(value: try container.decode(SRCompositionLayerShadowModifier.self))
            return
        case "brightnessBias":
            self = .compositionLayerBrightnessBiasModifier(value: try container.decode(SRCompositionLayerBrightnessBiasModifier.self))
            return
        case "saturate":
            self = .compositionLayerSaturateModifier(value: try container.decode(SRCompositionLayerSaturateModifier.self))
            return
        case "maskImage":
            self = .compositionLayerMaskImageModifier(value: try container.decode(SRCompositionLayerMaskImageModifier.self))
            return
        default:
            let error = DecodingError.Context(
                codingPath: discriminatorContainer.codingPath + [DiscriminatorCodingKeys.discriminator],
                debugDescription: """
                Failed to decode `SRCompositionLayerModifier`.
                Discriminator `type` did not match any known case.
                """
            )
            throw DecodingError.dataCorrupted(error)
        }
    }
}

/// Opacity applied to the composed layer output at this point in the modifier order.
@_spi(Internal)
public struct SRCompositionLayerOpacityModifier: Codable, Hashable {
    /// The type of the modifier.
    public let type: String = "opacity"

    /// Opacity value from 0 to 1.
    public let value: Double

    public enum CodingKeys: String, CodingKey {
        case type = "type"
        case value = "value"
    }

    /// Opacity applied to the composed layer output at this point in the modifier order.
    ///
    /// - Parameters:
    ///   - value: Opacity value from 0 to 1.
    public init(
        value: Double
    ) {
        self.value = value
    }
}

/// Applies a saturation adjustment to the rendered layer contents.
@_spi(Internal)
public struct SRCompositionLayerSaturateModifier: Codable, Hashable {
    /// The type of the modifier.
    public let type: String = "saturate"

    /// Saturation multiplier. 1 leaves content unchanged. 0 removes saturation.
    public let value: Double

    public enum CodingKeys: String, CodingKey {
        case type = "type"
        case value = "value"
    }

    /// Applies a saturation adjustment to the rendered layer contents.
    ///
    /// - Parameters:
    ///   - value: Saturation multiplier. 1 leaves content unchanged. 0 removes saturation.
    public init(
        value: Double
    ) {
        self.value = value
    }
}

/// Drop shadow drawn behind the composed layer output.
@_spi(Internal)
public struct SRCompositionLayerShadowModifier: Codable, Hashable {
    /// The shadow color as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional. SDKs should encode the effective shadow alpha in this color and omit the shadow modifier when the effective alpha is 0.
    public let color: String

    /// Horizontal shadow offset in pixels.
    public let offsetX: Double

    /// Vertical shadow offset in pixels.
    public let offsetY: Double

    /// Optional SVG path string defining the shadow outline, in coordinates local to the layer rectangle. When present, the path is interpreted using the non-zero winding rule. When omitted, the shadow follows the composed layer alpha.
    public let path: String?

    /// Blur radius used to create the shadow.
    public let radius: Double

    /// The type of the modifier.
    public let type: String = "shadow"

    public enum CodingKeys: String, CodingKey {
        case color = "color"
        case offsetX = "offsetX"
        case offsetY = "offsetY"
        case path = "path"
        case radius = "radius"
        case type = "type"
    }

    /// Drop shadow drawn behind the composed layer output.
    ///
    /// - Parameters:
    ///   - color: The shadow color as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional. SDKs should encode the effective shadow alpha in this color and omit the shadow modifier when the effective alpha is 0.
    ///   - offsetX: Horizontal shadow offset in pixels.
    ///   - offsetY: Vertical shadow offset in pixels.
    ///   - path: Optional SVG path string defining the shadow outline, in coordinates local to the layer rectangle. When present, the path is interpreted using the non-zero winding rule. When omitted, the shadow follows the composed layer alpha.
    ///   - radius: Blur radius used to create the shadow.
    public init(
        color: String,
        offsetX: Double,
        offsetY: Double,
        path: String? = nil,
        radius: Double
    ) {
        self.color = color
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.path = path
        self.radius = radius
    }
}

/// Sparse update for a composition layer. Omitted fields are unchanged.
@_spi(Internal)
public struct SRCompositionLayerUpdate: Codable, Hashable {
    /// When present, replaces the full child list for this layer.
    public let children: [SRCompositionLayerChild]?

    /// Updated composite operation for this layer.
    public let compositeOperation: CompositeOperation?

    /// Updated height in pixels. Uses the same coordinate space as mobile wireframes.
    public let height: Int64?

    /// The id of the layer to update.
    public let id: Int64

    /// When present, replaces the full modifier list for this layer.
    public let modifiers: [SRCompositionLayerModifier]?

    /// Updated width in pixels. Uses the same coordinate space as mobile wireframes.
    public let width: Int64?

    /// Updated X position in absolute coordinates. Uses the same coordinate space as mobile wireframes.
    public let x: Int64?

    /// Updated Y position in absolute coordinates. Uses the same coordinate space as mobile wireframes.
    public let y: Int64?

    public enum CodingKeys: String, CodingKey {
        case children = "children"
        case compositeOperation = "compositeOperation"
        case height = "height"
        case id = "id"
        case modifiers = "modifiers"
        case width = "width"
        case x = "x"
        case y = "y"
    }

    /// Sparse update for a composition layer. Omitted fields are unchanged.
    ///
    /// - Parameters:
    ///   - children: When present, replaces the full child list for this layer.
    ///   - compositeOperation: Updated composite operation for this layer.
    ///   - height: Updated height in pixels. Uses the same coordinate space as mobile wireframes.
    ///   - id: The id of the layer to update.
    ///   - modifiers: When present, replaces the full modifier list for this layer.
    ///   - width: Updated width in pixels. Uses the same coordinate space as mobile wireframes.
    ///   - x: Updated X position in absolute coordinates. Uses the same coordinate space as mobile wireframes.
    ///   - y: Updated Y position in absolute coordinates. Uses the same coordinate space as mobile wireframes.
    public init(
        children: [SRCompositionLayerChild]? = nil,
        compositeOperation: CompositeOperation? = nil,
        height: Int64? = nil,
        id: Int64,
        modifiers: [SRCompositionLayerModifier]? = nil,
        width: Int64? = nil,
        x: Int64? = nil,
        y: Int64? = nil
    ) {
        self.children = children
        self.compositeOperation = compositeOperation
        self.height = height
        self.id = id
        self.modifiers = modifiers
        self.width = width
        self.x = x
        self.y = y
    }

    /// Updated composite operation for this layer.
    @_spi(Internal)
    public enum CompositeOperation: String, Codable {
        case sourceOver = "sourceOver"
        case destinationIn = "destinationIn"
        case destinationOut = "destinationOut"
        case plusDarker = "plusDarker"
    }
}

/// Optional composition tree describing the rendering hierarchy. When present, the player uses this tree for rendering order and group operations.
@_spi(Internal)
public struct SRCompositionTree: Codable {
    /// Non-root composition layers referenced by the tree.
    public let layers: [SRCompositionLayer]?

    /// A rendering group that groups child wireframes and child layers. Does not draw pixels itself. Ordered rendering modifiers and compositing are applied to its composed output.
    public let root: SRCompositionLayer

    public enum CodingKeys: String, CodingKey {
        case layers = "layers"
        case root = "root"
    }

    /// Optional composition tree describing the rendering hierarchy. When present, the player uses this tree for rendering order and group operations.
    ///
    /// - Parameters:
    ///   - layers: Non-root composition layers referenced by the tree.
    ///   - root: A rendering group that groups child wireframes and child layers. Does not draw pixels itself. Ordered rendering modifiers and compositing are applied to its composed output.
    public init(
        layers: [SRCompositionLayer]? = nil,
        root: SRCompositionLayer
    ) {
        self.layers = layers
        self.root = root
    }
}

/// Mobile-specific. Incremental data carrying composition tree layer mutations.
@_spi(Internal)
public struct SRCompositionTreeMutationData: Codable {
    /// Full layer definitions for newly added layers.
    public let adds: [SRCompositionLayer]?

    /// Ids of layer definitions to remove. Removing a referenced layer also requires updating the parent or root child list.
    public let removes: [Int64]?

    /// A rendering group that groups child wireframes and child layers. Does not draw pixels itself. Ordered rendering modifiers and compositing are applied to its composed output.
    public let root: SRCompositionLayer?

    /// The source of this type of incremental data.
    public let source: Int64 = 10

    /// Sparse updates for existing layers.
    public let updates: [SRCompositionLayerUpdate]?

    public enum CodingKeys: String, CodingKey {
        case adds = "adds"
        case removes = "removes"
        case root = "root"
        case source = "source"
        case updates = "updates"
    }

    /// Mobile-specific. Incremental data carrying composition tree layer mutations.
    ///
    /// - Parameters:
    ///   - adds: Full layer definitions for newly added layers.
    ///   - removes: Ids of layer definitions to remove. Removing a referenced layer also requires updating the parent or root child list.
    ///   - root: A rendering group that groups child wireframes and child layers. Does not draw pixels itself. Ordered rendering modifiers and compositing are applied to its composed output.
    ///   - updates: Sparse updates for existing layers.
    public init(
        adds: [SRCompositionLayer]? = nil,
        removes: [Int64]? = nil,
        root: SRCompositionLayer? = nil,
        updates: [SRCompositionLayerUpdate]? = nil
    ) {
        self.adds = adds
        self.removes = removes
        self.root = root
        self.updates = updates
    }
}

/// Schema of clipping information for a Wireframe.
@_spi(Internal)
public struct SRContentClip: Codable, Hashable {
    /// The amount of space in pixels that needs to be clipped (masked) at the bottom of the wireframe.
    public let bottom: Int64?

    /// The amount of space in pixels that needs to be clipped (masked) at the left of the wireframe.
    public let left: Int64?

    /// The amount of space in pixels that needs to be clipped (masked) at the right of the wireframe.
    public let right: Int64?

    /// The amount of space in pixels that needs to be clipped (masked) at the top of the wireframe.
    public let top: Int64?

    public enum CodingKeys: String, CodingKey {
        case bottom = "bottom"
        case left = "left"
        case right = "right"
        case top = "top"
    }

    /// Schema of clipping information for a Wireframe.
    ///
    /// - Parameters:
    ///   - bottom: The amount of space in pixels that needs to be clipped (masked) at the bottom of the wireframe.
    ///   - left: The amount of space in pixels that needs to be clipped (masked) at the left of the wireframe.
    ///   - right: The amount of space in pixels that needs to be clipped (masked) at the right of the wireframe.
    ///   - top: The amount of space in pixels that needs to be clipped (masked) at the top of the wireframe.
    public init(
        bottom: Int64? = nil,
        left: Int64? = nil,
        right: Int64? = nil,
        top: Int64? = nil
    ) {
        self.bottom = bottom
        self.left = left
        self.right = right
        self.top = top
    }
}

/// Schema of all properties of an EmbeddedContentWireframe.
@_spi(Internal)
public struct SREmbeddedContentWireframe: Codable, Hashable {
    /// The border properties of this wireframe. The default value is null (no-border).
    public let border: SRShapeBorder?

    /// Schema of clipping information for a Wireframe.
    public let clip: SRContentClip?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    public let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    public let id: Int64

    /// Whether this embedded content is visible or not.
    public let isVisible: Bool?

    /// A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    public let permanentId: String?

    /// The style of this wireframe.
    public let shapeStyle: SRShapeStyle?

    /// Unique Id of the slot containing this embedded content.
    public let slotId: String

    /// The type of the wireframe.
    public let type: String = "embedded_content"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    public let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let y: Int64

    public enum CodingKeys: String, CodingKey {
        case border = "border"
        case clip = "clip"
        case height = "height"
        case id = "id"
        case isVisible = "isVisible"
        case permanentId = "permanentId"
        case shapeStyle = "shapeStyle"
        case slotId = "slotId"
        case type = "type"
        case width = "width"
        case x = "x"
        case y = "y"
    }

    /// Schema of all properties of an EmbeddedContentWireframe.
    ///
    /// - Parameters:
    ///   - border: The border properties of this wireframe. The default value is null (no-border).
    ///   - clip: Schema of clipping information for a Wireframe.
    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    ///   - isVisible: Whether this embedded content is visible or not.
    ///   - permanentId: A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    ///   - shapeStyle: The style of this wireframe.
    ///   - slotId: Unique Id of the slot containing this embedded content.
    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public init(
        border: SRShapeBorder? = nil,
        clip: SRContentClip? = nil,
        height: Int64,
        id: Int64,
        isVisible: Bool? = nil,
        permanentId: String? = nil,
        shapeStyle: SRShapeStyle? = nil,
        slotId: String,
        width: Int64,
        x: Int64,
        y: Int64
    ) {
        self.border = border
        self.clip = clip
        self.height = height
        self.id = id
        self.isVisible = isVisible
        self.permanentId = permanentId
        self.shapeStyle = shapeStyle
        self.slotId = slotId
        self.width = width
        self.x = x
        self.y = y
    }
}

/// Schema of a Record type which contains focus information.
@_spi(Internal)
public struct SRFocusRecord: Codable {
    public let data: Data

    /// Unique ID of the slot that generated this record.
    public let slotId: String?

    /// Defines the UTC time in milliseconds when this Record was performed.
    public let timestamp: Int64

    /// The type of this Record.
    public let type: Int64 = 6

    public enum CodingKeys: String, CodingKey {
        case data = "data"
        case slotId = "slotId"
        case timestamp = "timestamp"
        case type = "type"
    }

    /// Schema of a Record type which contains focus information.
    ///
    /// - Parameters:
    ///   - data:
    ///   - slotId: Unique ID of the slot that generated this record.
    ///   - timestamp: Defines the UTC time in milliseconds when this Record was performed.
    public init(
        data: Data,
        slotId: String? = nil,
        timestamp: Int64
    ) {
        self.data = data
        self.slotId = slotId
        self.timestamp = timestamp
    }

    @_spi(Internal)
    public struct Data: Codable {
        /// Whether this screen has a focus or not. For now it will always be true for mobile.
        public let hasFocus: Bool

        public enum CodingKeys: String, CodingKey {
            case hasFocus = "has_focus"
        }

        ///
        /// - Parameters:
        ///   - hasFocus: Whether this screen has a focus or not. For now it will always be true for mobile.
        public init(
            hasFocus: Bool
        ) {
            self.hasFocus = hasFocus
        }
    }
}

/// Mobile-specific. Schema of a Record type which contains the full snapshot of a screen.
@_spi(Internal)
public struct SRFullSnapshotRecord: Codable {
    public let data: Data

    /// Unique ID of the slot that generated this record.
    public let slotId: String?

    /// Defines the UTC time in milliseconds when this Record was performed.
    public let timestamp: Int64

    /// The type of this Record.
    public let type: Int64 = 10

    public enum CodingKeys: String, CodingKey {
        case data = "data"
        case slotId = "slotId"
        case timestamp = "timestamp"
        case type = "type"
    }

    /// Mobile-specific. Schema of a Record type which contains the full snapshot of a screen.
    ///
    /// - Parameters:
    ///   - data:
    ///   - slotId: Unique ID of the slot that generated this record.
    ///   - timestamp: Defines the UTC time in milliseconds when this Record was performed.
    public init(
        data: Data,
        slotId: String? = nil,
        timestamp: Int64
    ) {
        self.data = data
        self.slotId = slotId
        self.timestamp = timestamp
    }

    @_spi(Internal)
    public struct Data: Codable {
        /// Optional composition tree describing the rendering hierarchy. When present, the player uses this tree for rendering order and group operations.
        public let compositionTree: SRCompositionTree?

        /// The Wireframes contained by this Record.
        public let wireframes: [SRWireframe]

        public enum CodingKeys: String, CodingKey {
            case compositionTree = "compositionTree"
            case wireframes = "wireframes"
        }

        ///
        /// - Parameters:
        ///   - compositionTree: Optional composition tree describing the rendering hierarchy. When present, the player uses this tree for rendering order and group operations.
        ///   - wireframes: The Wireframes contained by this Record.
        public init(
            compositionTree: SRCompositionTree? = nil,
            wireframes: [SRWireframe]
        ) {
            self.compositionTree = compositionTree
            self.wireframes = wireframes
        }
    }
}

/// Schema of all properties of a ImageWireframe.
@_spi(Internal)
public struct SRImageWireframe: Codable, Hashable {
    /// base64 representation of the image. Not required as the ImageWireframe can be initialised without any base64
    public var base64: String?

    /// The border properties of this wireframe. The default value is null (no-border).
    public let border: SRShapeBorder?

    /// Schema of clipping information for a Wireframe.
    public let clip: SRContentClip?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    public let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    public let id: Int64

    /// Flag describing an image wireframe that should render an empty state placeholder
    public var isEmpty: Bool?

    /// MIME type of the image file
    public var mimeType: String?

    /// A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    public let permanentId: String?

    /// Unique identifier of the image resource
    public var resourceId: String?

    /// The style of this wireframe.
    public let shapeStyle: SRShapeStyle?

    /// The type of the wireframe.
    public let type: String = "image"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    public let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let y: Int64

    public enum CodingKeys: String, CodingKey {
        case base64 = "base64"
        case border = "border"
        case clip = "clip"
        case height = "height"
        case id = "id"
        case isEmpty = "isEmpty"
        case mimeType = "mimeType"
        case permanentId = "permanentId"
        case resourceId = "resourceId"
        case shapeStyle = "shapeStyle"
        case type = "type"
        case width = "width"
        case x = "x"
        case y = "y"
    }

    /// Schema of all properties of a ImageWireframe.
    ///
    /// - Parameters:
    ///   - base64: base64 representation of the image. Not required as the ImageWireframe can be initialised without any base64
    ///   - border: The border properties of this wireframe. The default value is null (no-border).
    ///   - clip: Schema of clipping information for a Wireframe.
    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    ///   - isEmpty: Flag describing an image wireframe that should render an empty state placeholder
    ///   - mimeType: MIME type of the image file
    ///   - permanentId: A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    ///   - resourceId: Unique identifier of the image resource
    ///   - shapeStyle: The style of this wireframe.
    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public init(
        base64: String? = nil,
        border: SRShapeBorder? = nil,
        clip: SRContentClip? = nil,
        height: Int64,
        id: Int64,
        isEmpty: Bool? = nil,
        mimeType: String? = nil,
        permanentId: String? = nil,
        resourceId: String? = nil,
        shapeStyle: SRShapeStyle? = nil,
        width: Int64,
        x: Int64,
        y: Int64
    ) {
        self.base64 = base64
        self.border = border
        self.clip = clip
        self.height = height
        self.id = id
        self.isEmpty = isEmpty
        self.mimeType = mimeType
        self.permanentId = permanentId
        self.resourceId = resourceId
        self.shapeStyle = shapeStyle
        self.width = width
        self.x = x
        self.y = y
    }
}

/// Mobile-specific. Schema of a Record type which contains mutations of a screen.
@_spi(Internal)
public struct SRIncrementalSnapshotRecord: Codable {
    /// Mobile-specific. Schema of a Session Replay IncrementalData type.
    public let data: Data

    /// Unique ID of the slot that generated this record.
    public let slotId: String?

    /// Defines the UTC time in milliseconds when this Record was performed.
    public let timestamp: Int64

    /// The type of this Record.
    public let type: Int64 = 11

    public enum CodingKeys: String, CodingKey {
        case data = "data"
        case slotId = "slotId"
        case timestamp = "timestamp"
        case type = "type"
    }

    /// Mobile-specific. Schema of a Record type which contains mutations of a screen.
    ///
    /// - Parameters:
    ///   - data: Mobile-specific. Schema of a Session Replay IncrementalData type.
    ///   - slotId: Unique ID of the slot that generated this record.
    ///   - timestamp: Defines the UTC time in milliseconds when this Record was performed.
    public init(
        data: Data,
        slotId: String? = nil,
        timestamp: Int64
    ) {
        self.data = data
        self.slotId = slotId
        self.timestamp = timestamp
    }

    /// Mobile-specific. Schema of a Session Replay IncrementalData type.
    @_spi(Internal)
    public enum Data: Codable {
        case mutationData(value: MutationData)
        case touchData(value: TouchData)
        case viewportResizeData(value: ViewportResizeData)
        case pointerInteractionData(value: PointerInteractionData)
        case compositionTreeMutationData(value: SRCompositionTreeMutationData)

        private enum DiscriminatorCodingKeys: String, CodingKey {
            case discriminator = "source"
        }

        // MARK: - Codable

        public func encode(to encoder: Encoder) throws {
            // Encode only the associated value, without encoding enum case
            var container = encoder.singleValueContainer()

            switch self {
            case .mutationData(let value):
                try container.encode(value)
            case .touchData(let value):
                try container.encode(value)
            case .viewportResizeData(let value):
                try container.encode(value)
            case .pointerInteractionData(let value):
                try container.encode(value)
            case .compositionTreeMutationData(let value):
                try container.encode(value)
            }
        }

        public init(from decoder: Decoder) throws {
            // Decode enum case from discriminator
            let container = try decoder.singleValueContainer()
            let discriminatorContainer = try decoder.container(keyedBy: DiscriminatorCodingKeys.self)

            switch try discriminatorContainer.decode(Int64.self, forKey: .discriminator) {
            case 0:
                self = .mutationData(value: try container.decode(MutationData.self))
                return
            case 2:
                self = .touchData(value: try container.decode(TouchData.self))
                return
            case 4:
                self = .viewportResizeData(value: try container.decode(ViewportResizeData.self))
                return
            case 9:
                self = .pointerInteractionData(value: try container.decode(PointerInteractionData.self))
                return
            case 10:
                self = .compositionTreeMutationData(value: try container.decode(SRCompositionTreeMutationData.self))
                return
            default:
                let error = DecodingError.Context(
                    codingPath: discriminatorContainer.codingPath + [DiscriminatorCodingKeys.discriminator],
                    debugDescription: """
                    Failed to decode `Data`.
                    Discriminator `source` did not match any known case.
                    """
                )
                throw DecodingError.dataCorrupted(error)
            }
        }

        /// Mobile-specific. Schema of a MutationData.
        @_spi(Internal)
        public struct MutationData: Codable {
            /// Contains the newly added wireframes.
            public let adds: [Adds]

            /// Contains the removed wireframes as an array of ids.
            public let removes: [Removes]

            /// The source of this type of incremental data.
            public let source: Int64 = 0

            /// Contains the updated wireframes mutations.
            public let updates: [Updates]

            public enum CodingKeys: String, CodingKey {
                case adds = "adds"
                case removes = "removes"
                case source = "source"
                case updates = "updates"
            }

            /// Mobile-specific. Schema of a MutationData.
            ///
            /// - Parameters:
            ///   - adds: Contains the newly added wireframes.
            ///   - removes: Contains the removed wireframes as an array of ids.
            ///   - updates: Contains the updated wireframes mutations.
            public init(
                adds: [Adds],
                removes: [Removes],
                updates: [Updates]
            ) {
                self.adds = adds
                self.removes = removes
                self.updates = updates
            }

            @_spi(Internal)
            public struct Adds: Codable {
                /// The previous wireframe id next or after which this new wireframe is drawn or attached to, respectively.
                public let previousId: Int64?

                /// Schema of a Wireframe type.
                public let wireframe: SRWireframe

                public enum CodingKeys: String, CodingKey {
                    case previousId = "previousId"
                    case wireframe = "wireframe"
                }

                ///
                /// - Parameters:
                ///   - previousId: The previous wireframe id next or after which this new wireframe is drawn or attached to, respectively.
                ///   - wireframe: Schema of a Wireframe type.
                public init(
                    previousId: Int64? = nil,
                    wireframe: SRWireframe
                ) {
                    self.previousId = previousId
                    self.wireframe = wireframe
                }
            }

            @_spi(Internal)
            public struct Removes: Codable {
                /// The id of the wireframe that needs to be removed.
                public let id: Int64

                public enum CodingKeys: String, CodingKey {
                    case id = "id"
                }

                ///
                /// - Parameters:
                ///   - id: The id of the wireframe that needs to be removed.
                public init(
                    id: Int64
                ) {
                    self.id = id
                }
            }

            /// Schema of a WireframeUpdateMutation type.
            @_spi(Internal)
            public enum Updates: Codable {
                case textWireframeUpdate(value: TextWireframeUpdate)
                case shapeWireframeUpdate(value: ShapeWireframeUpdate)
                case imageWireframeUpdate(value: ImageWireframeUpdate)
                case placeholderWireframeUpdate(value: PlaceholderWireframeUpdate)
                case webviewWireframeUpdate(value: WebviewWireframeUpdate)
                case embeddedContentWireframeUpdate(value: EmbeddedContentWireframeUpdate)

                private enum DiscriminatorCodingKeys: String, CodingKey {
                    case discriminator = "type"
                }

                // MARK: - Codable

                public func encode(to encoder: Encoder) throws {
                    // Encode only the associated value, without encoding enum case
                    var container = encoder.singleValueContainer()

                    switch self {
                    case .textWireframeUpdate(let value):
                        try container.encode(value)
                    case .shapeWireframeUpdate(let value):
                        try container.encode(value)
                    case .imageWireframeUpdate(let value):
                        try container.encode(value)
                    case .placeholderWireframeUpdate(let value):
                        try container.encode(value)
                    case .webviewWireframeUpdate(let value):
                        try container.encode(value)
                    case .embeddedContentWireframeUpdate(let value):
                        try container.encode(value)
                    }
                }

                public init(from decoder: Decoder) throws {
                    // Decode enum case from discriminator
                    let container = try decoder.singleValueContainer()
                    let discriminatorContainer = try decoder.container(keyedBy: DiscriminatorCodingKeys.self)

                    switch try discriminatorContainer.decode(String.self, forKey: .discriminator) {
                    case "text":
                        self = .textWireframeUpdate(value: try container.decode(TextWireframeUpdate.self))
                        return
                    case "shape":
                        self = .shapeWireframeUpdate(value: try container.decode(ShapeWireframeUpdate.self))
                        return
                    case "image":
                        self = .imageWireframeUpdate(value: try container.decode(ImageWireframeUpdate.self))
                        return
                    case "placeholder":
                        self = .placeholderWireframeUpdate(value: try container.decode(PlaceholderWireframeUpdate.self))
                        return
                    case "webview":
                        self = .webviewWireframeUpdate(value: try container.decode(WebviewWireframeUpdate.self))
                        return
                    case "embedded_content":
                        self = .embeddedContentWireframeUpdate(value: try container.decode(EmbeddedContentWireframeUpdate.self))
                        return
                    default:
                        let error = DecodingError.Context(
                            codingPath: discriminatorContainer.codingPath + [DiscriminatorCodingKeys.discriminator],
                            debugDescription: """
                            Failed to decode `Updates`.
                            Discriminator `type` did not match any known case.
                            """
                        )
                        throw DecodingError.dataCorrupted(error)
                    }
                }

                /// Schema of all properties of a TextWireframeUpdate.
                @_spi(Internal)
                public struct TextWireframeUpdate: Codable {
                    /// The border properties of this wireframe. The default value is null (no-border).
                    public let border: SRShapeBorder?

                    /// Schema of clipping information for a Wireframe.
                    public let clip: SRContentClip?

                    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    public let height: Int64?

                    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    public let id: Int64

                    /// The style of this wireframe.
                    public let shapeStyle: SRShapeStyle?

                    /// The text value of the wireframe.
                    public var text: String?

                    /// Schema of all properties of a TextPosition.
                    public let textPosition: SRTextPosition?

                    /// Schema of all properties of a TextStyle.
                    public let textStyle: SRTextStyle?

                    /// The type of the wireframe.
                    public let type: String = "text"

                    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    public let width: Int64?

                    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let x: Int64?

                    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let y: Int64?

                    public enum CodingKeys: String, CodingKey {
                        case border = "border"
                        case clip = "clip"
                        case height = "height"
                        case id = "id"
                        case shapeStyle = "shapeStyle"
                        case text = "text"
                        case textPosition = "textPosition"
                        case textStyle = "textStyle"
                        case type = "type"
                        case width = "width"
                        case x = "x"
                        case y = "y"
                    }

                    /// Schema of all properties of a TextWireframeUpdate.
                    ///
                    /// - Parameters:
                    ///   - border: The border properties of this wireframe. The default value is null (no-border).
                    ///   - clip: Schema of clipping information for a Wireframe.
                    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    ///   - shapeStyle: The style of this wireframe.
                    ///   - text: The text value of the wireframe.
                    ///   - textPosition: Schema of all properties of a TextPosition.
                    ///   - textStyle: Schema of all properties of a TextStyle.
                    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public init(
                        border: SRShapeBorder? = nil,
                        clip: SRContentClip? = nil,
                        height: Int64? = nil,
                        id: Int64,
                        shapeStyle: SRShapeStyle? = nil,
                        text: String? = nil,
                        textPosition: SRTextPosition? = nil,
                        textStyle: SRTextStyle? = nil,
                        width: Int64? = nil,
                        x: Int64? = nil,
                        y: Int64? = nil
                    ) {
                        self.border = border
                        self.clip = clip
                        self.height = height
                        self.id = id
                        self.shapeStyle = shapeStyle
                        self.text = text
                        self.textPosition = textPosition
                        self.textStyle = textStyle
                        self.width = width
                        self.x = x
                        self.y = y
                    }
                }

                /// Schema of a ShapeWireframeUpdate.
                @_spi(Internal)
                public struct ShapeWireframeUpdate: Codable {
                    /// The border properties of this wireframe. The default value is null (no-border).
                    public let border: SRShapeBorder?

                    /// Schema of clipping information for a Wireframe.
                    public let clip: SRContentClip?

                    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    public let height: Int64?

                    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    public let id: Int64

                    /// The style of this wireframe.
                    public let shapeStyle: SRShapeStyle?

                    /// The type of the wireframe.
                    public let type: String = "shape"

                    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    public let width: Int64?

                    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let x: Int64?

                    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let y: Int64?

                    public enum CodingKeys: String, CodingKey {
                        case border = "border"
                        case clip = "clip"
                        case height = "height"
                        case id = "id"
                        case shapeStyle = "shapeStyle"
                        case type = "type"
                        case width = "width"
                        case x = "x"
                        case y = "y"
                    }

                    /// Schema of a ShapeWireframeUpdate.
                    ///
                    /// - Parameters:
                    ///   - border: The border properties of this wireframe. The default value is null (no-border).
                    ///   - clip: Schema of clipping information for a Wireframe.
                    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    ///   - shapeStyle: The style of this wireframe.
                    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public init(
                        border: SRShapeBorder? = nil,
                        clip: SRContentClip? = nil,
                        height: Int64? = nil,
                        id: Int64,
                        shapeStyle: SRShapeStyle? = nil,
                        width: Int64? = nil,
                        x: Int64? = nil,
                        y: Int64? = nil
                    ) {
                        self.border = border
                        self.clip = clip
                        self.height = height
                        self.id = id
                        self.shapeStyle = shapeStyle
                        self.width = width
                        self.x = x
                        self.y = y
                    }
                }

                /// Schema of all properties of a ImageWireframeUpdate.
                @_spi(Internal)
                public struct ImageWireframeUpdate: Codable {
                    /// base64 representation of the image. Not required as the ImageWireframe can be initialised without any base64
                    public var base64: String?

                    /// The border properties of this wireframe. The default value is null (no-border).
                    public let border: SRShapeBorder?

                    /// Schema of clipping information for a Wireframe.
                    public let clip: SRContentClip?

                    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    public let height: Int64?

                    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    public let id: Int64

                    /// Flag describing an image wireframe that should render an empty state placeholder
                    public var isEmpty: Bool?

                    /// MIME type of the image file
                    public var mimeType: String?

                    /// Unique identifier of the image resource
                    public var resourceId: String?

                    /// The style of this wireframe.
                    public let shapeStyle: SRShapeStyle?

                    /// The type of the wireframe.
                    public let type: String = "image"

                    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    public let width: Int64?

                    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let x: Int64?

                    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let y: Int64?

                    public enum CodingKeys: String, CodingKey {
                        case base64 = "base64"
                        case border = "border"
                        case clip = "clip"
                        case height = "height"
                        case id = "id"
                        case isEmpty = "isEmpty"
                        case mimeType = "mimeType"
                        case resourceId = "resourceId"
                        case shapeStyle = "shapeStyle"
                        case type = "type"
                        case width = "width"
                        case x = "x"
                        case y = "y"
                    }

                    /// Schema of all properties of a ImageWireframeUpdate.
                    ///
                    /// - Parameters:
                    ///   - base64: base64 representation of the image. Not required as the ImageWireframe can be initialised without any base64
                    ///   - border: The border properties of this wireframe. The default value is null (no-border).
                    ///   - clip: Schema of clipping information for a Wireframe.
                    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    ///   - isEmpty: Flag describing an image wireframe that should render an empty state placeholder
                    ///   - mimeType: MIME type of the image file
                    ///   - resourceId: Unique identifier of the image resource
                    ///   - shapeStyle: The style of this wireframe.
                    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public init(
                        base64: String? = nil,
                        border: SRShapeBorder? = nil,
                        clip: SRContentClip? = nil,
                        height: Int64? = nil,
                        id: Int64,
                        isEmpty: Bool? = nil,
                        mimeType: String? = nil,
                        resourceId: String? = nil,
                        shapeStyle: SRShapeStyle? = nil,
                        width: Int64? = nil,
                        x: Int64? = nil,
                        y: Int64? = nil
                    ) {
                        self.base64 = base64
                        self.border = border
                        self.clip = clip
                        self.height = height
                        self.id = id
                        self.isEmpty = isEmpty
                        self.mimeType = mimeType
                        self.resourceId = resourceId
                        self.shapeStyle = shapeStyle
                        self.width = width
                        self.x = x
                        self.y = y
                    }
                }

                /// Schema of all properties of a PlaceholderWireframe.
                @_spi(Internal)
                public struct PlaceholderWireframeUpdate: Codable {
                    /// Schema of clipping information for a Wireframe.
                    public let clip: SRContentClip?

                    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    public let height: Int64?

                    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    public let id: Int64

                    /// Label of the placeholder
                    public var label: String?

                    /// The type of the wireframe.
                    public let type: String = "placeholder"

                    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    public let width: Int64?

                    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let x: Int64?

                    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let y: Int64?

                    public enum CodingKeys: String, CodingKey {
                        case clip = "clip"
                        case height = "height"
                        case id = "id"
                        case label = "label"
                        case type = "type"
                        case width = "width"
                        case x = "x"
                        case y = "y"
                    }

                    /// Schema of all properties of a PlaceholderWireframe.
                    ///
                    /// - Parameters:
                    ///   - clip: Schema of clipping information for a Wireframe.
                    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    ///   - label: Label of the placeholder
                    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public init(
                        clip: SRContentClip? = nil,
                        height: Int64? = nil,
                        id: Int64,
                        label: String? = nil,
                        width: Int64? = nil,
                        x: Int64? = nil,
                        y: Int64? = nil
                    ) {
                        self.clip = clip
                        self.height = height
                        self.id = id
                        self.label = label
                        self.width = width
                        self.x = x
                        self.y = y
                    }
                }

                /// Schema of all properties of a WebviewWireframeUpdate.
                @_spi(Internal)
                public struct WebviewWireframeUpdate: Codable {
                    /// The border properties of this wireframe. The default value is null (no-border).
                    public let border: SRShapeBorder?

                    /// Schema of clipping information for a Wireframe.
                    public let clip: SRContentClip?

                    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    public let height: Int64?

                    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    public let id: Int64

                    /// Whether this webview is visible or not.
                    public let isVisible: Bool?

                    /// The style of this wireframe.
                    public let shapeStyle: SRShapeStyle?

                    /// Unique Id of the slot containing this webview.
                    public let slotId: String

                    /// The type of the wireframe.
                    public let type: String = "webview"

                    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    public let width: Int64?

                    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let x: Int64?

                    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let y: Int64?

                    public enum CodingKeys: String, CodingKey {
                        case border = "border"
                        case clip = "clip"
                        case height = "height"
                        case id = "id"
                        case isVisible = "isVisible"
                        case shapeStyle = "shapeStyle"
                        case slotId = "slotId"
                        case type = "type"
                        case width = "width"
                        case x = "x"
                        case y = "y"
                    }

                    /// Schema of all properties of a WebviewWireframeUpdate.
                    ///
                    /// - Parameters:
                    ///   - border: The border properties of this wireframe. The default value is null (no-border).
                    ///   - clip: Schema of clipping information for a Wireframe.
                    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    ///   - isVisible: Whether this webview is visible or not.
                    ///   - shapeStyle: The style of this wireframe.
                    ///   - slotId: Unique Id of the slot containing this webview.
                    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public init(
                        border: SRShapeBorder? = nil,
                        clip: SRContentClip? = nil,
                        height: Int64? = nil,
                        id: Int64,
                        isVisible: Bool? = nil,
                        shapeStyle: SRShapeStyle? = nil,
                        slotId: String,
                        width: Int64? = nil,
                        x: Int64? = nil,
                        y: Int64? = nil
                    ) {
                        self.border = border
                        self.clip = clip
                        self.height = height
                        self.id = id
                        self.isVisible = isVisible
                        self.shapeStyle = shapeStyle
                        self.slotId = slotId
                        self.width = width
                        self.x = x
                        self.y = y
                    }
                }

                /// Schema of all properties of an EmbeddedContentWireframeUpdate.
                @_spi(Internal)
                public struct EmbeddedContentWireframeUpdate: Codable {
                    /// The border properties of this wireframe. The default value is null (no-border).
                    public let border: SRShapeBorder?

                    /// Schema of clipping information for a Wireframe.
                    public let clip: SRContentClip?

                    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    public let height: Int64?

                    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    public let id: Int64

                    /// Whether this embedded content is visible or not.
                    public let isVisible: Bool?

                    /// The style of this wireframe.
                    public let shapeStyle: SRShapeStyle?

                    /// Unique Id of the slot containing this embedded content.
                    public let slotId: String

                    /// The type of the wireframe.
                    public let type: String = "embedded_content"

                    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    public let width: Int64?

                    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let x: Int64?

                    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public let y: Int64?

                    public enum CodingKeys: String, CodingKey {
                        case border = "border"
                        case clip = "clip"
                        case height = "height"
                        case id = "id"
                        case isVisible = "isVisible"
                        case shapeStyle = "shapeStyle"
                        case slotId = "slotId"
                        case type = "type"
                        case width = "width"
                        case x = "x"
                        case y = "y"
                    }

                    /// Schema of all properties of an EmbeddedContentWireframeUpdate.
                    ///
                    /// - Parameters:
                    ///   - border: The border properties of this wireframe. The default value is null (no-border).
                    ///   - clip: Schema of clipping information for a Wireframe.
                    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    ///   - isVisible: Whether this embedded content is visible or not.
                    ///   - shapeStyle: The style of this wireframe.
                    ///   - slotId: Unique Id of the slot containing this embedded content.
                    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    public init(
                        border: SRShapeBorder? = nil,
                        clip: SRContentClip? = nil,
                        height: Int64? = nil,
                        id: Int64,
                        isVisible: Bool? = nil,
                        shapeStyle: SRShapeStyle? = nil,
                        slotId: String,
                        width: Int64? = nil,
                        x: Int64? = nil,
                        y: Int64? = nil
                    ) {
                        self.border = border
                        self.clip = clip
                        self.height = height
                        self.id = id
                        self.isVisible = isVisible
                        self.shapeStyle = shapeStyle
                        self.slotId = slotId
                        self.width = width
                        self.x = x
                        self.y = y
                    }
                }
            }
        }

        /// Schema of a TouchData.
        @_spi(Internal)
        public struct TouchData: Codable {
            /// Contains the positions of the finger on the screen during the touchDown/touchUp event lifecycle.
            public let positions: [Positions]?

            /// The source of this type of incremental data.
            public let source: Int64 = 2

            public enum CodingKeys: String, CodingKey {
                case positions = "positions"
                case source = "source"
            }

            /// Schema of a TouchData.
            ///
            /// - Parameters:
            ///   - positions: Contains the positions of the finger on the screen during the touchDown/touchUp event lifecycle.
            public init(
                positions: [Positions]? = nil
            ) {
                self.positions = positions
            }

            @_spi(Internal)
            public struct Positions: Codable {
                /// The touch id of the touch event this position corresponds to. In mobile it is possible to have multiple touch events (fingers touching the screen) happening at the same time.
                public let id: Int64

                /// The UTC timestamp in milliseconds corresponding to the moment the position change was recorded. Each timestamp is computed as the UTC interval since 00:00:00.000 01.01.1970.
                public let timestamp: Int64

                /// The x coordinate value of the position.
                public let x: Int64

                /// The y coordinate value of the position.
                public let y: Int64

                public enum CodingKeys: String, CodingKey {
                    case id = "id"
                    case timestamp = "timestamp"
                    case x = "x"
                    case y = "y"
                }

                ///
                /// - Parameters:
                ///   - id: The touch id of the touch event this position corresponds to. In mobile it is possible to have multiple touch events (fingers touching the screen) happening at the same time.
                ///   - timestamp: The UTC timestamp in milliseconds corresponding to the moment the position change was recorded. Each timestamp is computed as the UTC interval since 00:00:00.000 01.01.1970.
                ///   - x: The x coordinate value of the position.
                ///   - y: The y coordinate value of the position.
                public init(
                    id: Int64,
                    timestamp: Int64,
                    x: Int64,
                    y: Int64
                ) {
                    self.id = id
                    self.timestamp = timestamp
                    self.x = x
                    self.y = y
                }
            }
        }

        /// Schema of a ViewportResizeData.
        @_spi(Internal)
        public struct ViewportResizeData: Codable {
            /// The new height of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height is divided by 2 to get a normalized height.
            public let height: Int64

            /// The source of this type of incremental data.
            public let source: Int64 = 4

            /// The new width of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width is divided by 2 to get a normalized width.
            public let width: Int64

            public enum CodingKeys: String, CodingKey {
                case height = "height"
                case source = "source"
                case width = "width"
            }

            /// Schema of a ViewportResizeData.
            ///
            /// - Parameters:
            ///   - height: The new height of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height is divided by 2 to get a normalized height.
            ///   - width: The new width of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width is divided by 2 to get a normalized width.
            public init(
                height: Int64,
                width: Int64
            ) {
                self.height = height
                self.width = width
            }
        }

        /// Schema of a PointerInteractionData.
        @_spi(Internal)
        public struct PointerInteractionData: Codable {
            /// Schema of an PointerEventType
            public let pointerEventType: PointerEventType

            /// Id of the pointer of this PointerInteraction.
            public let pointerId: Int64

            /// Schema of an PointerType
            public let pointerType: PointerType

            /// The source of this type of incremental data.
            public let source: Int64 = 9

            /// X-axis coordinate for this PointerInteraction.
            public let x: Double

            /// Y-axis coordinate for this PointerInteraction.
            public let y: Double

            public enum CodingKeys: String, CodingKey {
                case pointerEventType = "pointerEventType"
                case pointerId = "pointerId"
                case pointerType = "pointerType"
                case source = "source"
                case x = "x"
                case y = "y"
            }

            /// Schema of a PointerInteractionData.
            ///
            /// - Parameters:
            ///   - pointerEventType: Schema of an PointerEventType
            ///   - pointerId: Id of the pointer of this PointerInteraction.
            ///   - pointerType: Schema of an PointerType
            ///   - x: X-axis coordinate for this PointerInteraction.
            ///   - y: Y-axis coordinate for this PointerInteraction.
            public init(
                pointerEventType: PointerEventType,
                pointerId: Int64,
                pointerType: PointerType,
                x: Double,
                y: Double
            ) {
                self.pointerEventType = pointerEventType
                self.pointerId = pointerId
                self.pointerType = pointerType
                self.x = x
                self.y = y
            }

            /// Schema of an PointerEventType
            @_spi(Internal)
            public enum PointerEventType: String, Codable {
                case down = "down"
                case up = "up"
                case move = "move"
            }

            /// Schema of an PointerType
            @_spi(Internal)
            public enum PointerType: String, Codable {
                case mouse = "mouse"
                case touch = "touch"
                case pen = "pen"
            }
        }
    }
}

/// Schema of a Record which contains the screen properties.
@_spi(Internal)
public struct SRMetaRecord: Codable {
    /// The data contained by this record.
    public let data: Data

    /// Unique ID of the slot that generated this record.
    public let slotId: String?

    /// Defines the UTC time in milliseconds when this Record was performed.
    public let timestamp: Int64

    /// The type of this Record.
    public let type: Int64 = 4

    public enum CodingKeys: String, CodingKey {
        case data = "data"
        case slotId = "slotId"
        case timestamp = "timestamp"
        case type = "type"
    }

    /// Schema of a Record which contains the screen properties.
    ///
    /// - Parameters:
    ///   - data: The data contained by this record.
    ///   - slotId: Unique ID of the slot that generated this record.
    ///   - timestamp: Defines the UTC time in milliseconds when this Record was performed.
    public init(
        data: Data,
        slotId: String? = nil,
        timestamp: Int64
    ) {
        self.data = data
        self.slotId = slotId
        self.timestamp = timestamp
    }

    /// The data contained by this record.
    @_spi(Internal)
    public struct Data: Codable {
        /// The height of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the normalized height is the current height divided by 2.
        public let height: Int64

        /// Browser-specific. URL of the view described by this record.
        public let href: String?

        /// The width of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the normalized width is the current width divided by 2.
        public let width: Int64

        public enum CodingKeys: String, CodingKey {
            case height = "height"
            case href = "href"
            case width = "width"
        }

        /// The data contained by this record.
        ///
        /// - Parameters:
        ///   - height: The height of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the normalized height is the current height divided by 2.
        ///   - href: Browser-specific. URL of the view described by this record.
        ///   - width: The width of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the normalized width is the current width divided by 2.
        public init(
            height: Int64,
            href: String? = nil,
            width: Int64
        ) {
            self.height = height
            self.href = href
            self.width = width
        }
    }
}

/// Schema of all properties of a PlaceholderWireframe.
@_spi(Internal)
public struct SRPlaceholderWireframe: Codable, Hashable {
    /// Schema of clipping information for a Wireframe.
    public let clip: SRContentClip?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    public let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    public let id: Int64

    /// Label of the placeholder
    public var label: String?

    /// A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    public let permanentId: String?

    /// The type of the wireframe.
    public let type: String = "placeholder"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    public let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let y: Int64

    public enum CodingKeys: String, CodingKey {
        case clip = "clip"
        case height = "height"
        case id = "id"
        case label = "label"
        case permanentId = "permanentId"
        case type = "type"
        case width = "width"
        case x = "x"
        case y = "y"
    }

    /// Schema of all properties of a PlaceholderWireframe.
    ///
    /// - Parameters:
    ///   - clip: Schema of clipping information for a Wireframe.
    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    ///   - label: Label of the placeholder
    ///   - permanentId: A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public init(
        clip: SRContentClip? = nil,
        height: Int64,
        id: Int64,
        label: String? = nil,
        permanentId: String? = nil,
        width: Int64,
        x: Int64,
        y: Int64
    ) {
        self.clip = clip
        self.height = height
        self.id = id
        self.label = label
        self.permanentId = permanentId
        self.width = width
        self.x = x
        self.y = y
    }
}

/// Mobile-specific. Schema of a Session Replay Record.
@_spi(Internal)
public enum SRRecord: Codable {
    case fullSnapshotRecord(value: SRFullSnapshotRecord)
    case incrementalSnapshotRecord(value: SRIncrementalSnapshotRecord)
    case metaRecord(value: SRMetaRecord)
    case focusRecord(value: SRFocusRecord)
    case viewEndRecord(value: SRViewEndRecord)
    case visualViewportRecord(value: SRVisualViewportRecord)

    // MARK: - Codable

    public func encode(to encoder: Encoder) throws {
        // Encode only the associated value, without encoding enum case
        var container = encoder.singleValueContainer()

        switch self {
        case .fullSnapshotRecord(let value):
            try container.encode(value)
        case .incrementalSnapshotRecord(let value):
            try container.encode(value)
        case .metaRecord(let value):
            try container.encode(value)
        case .focusRecord(let value):
            try container.encode(value)
        case .viewEndRecord(let value):
            try container.encode(value)
        case .visualViewportRecord(let value):
            try container.encode(value)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode enum case from associated value
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(SRFullSnapshotRecord.self) {
            self = .fullSnapshotRecord(value: value)
            return
        }
        if let value = try? container.decode(SRIncrementalSnapshotRecord.self) {
            self = .incrementalSnapshotRecord(value: value)
            return
        }
        if let value = try? container.decode(SRMetaRecord.self) {
            self = .metaRecord(value: value)
            return
        }
        if let value = try? container.decode(SRFocusRecord.self) {
            self = .focusRecord(value: value)
            return
        }
        if let value = try? container.decode(SRViewEndRecord.self) {
            self = .viewEndRecord(value: value)
            return
        }
        if let value = try? container.decode(SRVisualViewportRecord.self) {
            self = .visualViewportRecord(value: value)
            return
        }
        let error = DecodingError.Context(
            codingPath: container.codingPath,
            debugDescription: """
            Failed to decode `SRRecord`.
            Ran out of possibilities when trying to decode the value of associated type.
            """
        )
        throw DecodingError.typeMismatch(SRRecord.self, error)
    }
}

/// Mobile-specific. Schema of a Session Replay data Segment.
@_spi(Internal)
public struct SRSegment: SRDataModel {
    /// Application properties
    public let application: Application

    /// The end UTC timestamp in milliseconds corresponding to the last record in the Segment data. Each timestamp is computed as the UTC interval since 00:00:00.000 01.01.1970.
    public let end: Int64

    /// Whether this Segment contains a full snapshot record or not.
    public let hasFullSnapshot: Bool?

    /// The index of this Segment in the segments list that was recorded for this view ID. Starts from 0.
    public let indexInView: Int64?

    /// The records contained by this Segment.
    public let records: [SRRecord]

    /// The number of records in this Segment.
    public let recordsCount: Int64

    /// Session properties
    public let session: Session

    /// The source of this record
    public let source: Source

    /// The start UTC timestamp in milliseconds corresponding to the first record in the Segment data. Each timestamp is computed as the UTC interval since 00:00:00.000 01.01.1970.
    public let start: Int64

    /// View properties
    public let view: View

    public enum CodingKeys: String, CodingKey {
        case application = "application"
        case end = "end"
        case hasFullSnapshot = "has_full_snapshot"
        case indexInView = "index_in_view"
        case records = "records"
        case recordsCount = "records_count"
        case session = "session"
        case source = "source"
        case start = "start"
        case view = "view"
    }

    /// Mobile-specific. Schema of a Session Replay data Segment.
    ///
    /// - Parameters:
    ///   - application: Application properties
    ///   - end: The end UTC timestamp in milliseconds corresponding to the last record in the Segment data. Each timestamp is computed as the UTC interval since 00:00:00.000 01.01.1970.
    ///   - hasFullSnapshot: Whether this Segment contains a full snapshot record or not.
    ///   - indexInView: The index of this Segment in the segments list that was recorded for this view ID. Starts from 0.
    ///   - records: The records contained by this Segment.
    ///   - recordsCount: The number of records in this Segment.
    ///   - session: Session properties
    ///   - source: The source of this record
    ///   - start: The start UTC timestamp in milliseconds corresponding to the first record in the Segment data. Each timestamp is computed as the UTC interval since 00:00:00.000 01.01.1970.
    ///   - view: View properties
    public init(
        application: Application,
        end: Int64,
        hasFullSnapshot: Bool? = nil,
        indexInView: Int64? = nil,
        records: [SRRecord],
        recordsCount: Int64,
        session: Session,
        source: Source,
        start: Int64,
        view: View
    ) {
        self.application = application
        self.end = end
        self.hasFullSnapshot = hasFullSnapshot
        self.indexInView = indexInView
        self.records = records
        self.recordsCount = recordsCount
        self.session = session
        self.source = source
        self.start = start
        self.view = view
    }

    /// Application properties
    @_spi(Internal)
    public struct Application: Codable {
        /// UUID of the application
        public let id: String

        public enum CodingKeys: String, CodingKey {
            case id = "id"
        }

        /// Application properties
        ///
        /// - Parameters:
        ///   - id: UUID of the application
        public init(
            id: String
        ) {
            self.id = id
        }
    }

    /// Session properties
    @_spi(Internal)
    public struct Session: Codable {
        /// UUID of the session
        public let id: String

        public enum CodingKeys: String, CodingKey {
            case id = "id"
        }

        /// Session properties
        ///
        /// - Parameters:
        ///   - id: UUID of the session
        public init(
            id: String
        ) {
            self.id = id
        }
    }

    /// The source of this record
    @_spi(Internal)
    public enum Source: String, Codable {
        case android = "android"
        case ios = "ios"
        case flutter = "flutter"
        case reactNative = "react-native"
        case kotlinMultiplatform = "kotlin-multiplatform"
        case maui = "maui"
    }

    /// View properties
    @_spi(Internal)
    public struct View: Codable {
        /// UUID of the view
        public let id: String

        public enum CodingKeys: String, CodingKey {
            case id = "id"
        }

        /// View properties
        ///
        /// - Parameters:
        ///   - id: UUID of the view
        public init(
            id: String
        ) {
            self.id = id
        }
    }
}

/// The border properties of this wireframe. The default value is null (no-border).
@_spi(Internal)
public struct SRShapeBorder: Codable, Hashable {
    /// The border color as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
    public let color: String

    /// The width of the border in pixels.
    public let width: Int64

    public enum CodingKeys: String, CodingKey {
        case color = "color"
        case width = "width"
    }

    /// The border properties of this wireframe. The default value is null (no-border).
    ///
    /// - Parameters:
    ///   - color: The border color as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
    ///   - width: The width of the border in pixels.
    public init(
        color: String,
        width: Int64
    ) {
        self.color = color
        self.width = width
    }
}

/// The background gradient for this wireframe.
@_spi(Internal)
public enum SRShapeGradient: Codable, Hashable {
    case linear(value: SRShapeLinearGradient)

    private enum DiscriminatorCodingKeys: String, CodingKey {
        case discriminator = "type"
    }

    // MARK: - Codable

    public func encode(to encoder: Encoder) throws {
        // Encode only the associated value, without encoding enum case
        var container = encoder.singleValueContainer()

        switch self {
        case .linear(let value):
            try container.encode(value)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode enum case from discriminator
        let container = try decoder.singleValueContainer()
        let discriminatorContainer = try decoder.container(keyedBy: DiscriminatorCodingKeys.self)

        switch try discriminatorContainer.decode(String.self, forKey: .discriminator) {
        case "linear":
            self = .linear(value: try container.decode(SRShapeLinearGradient.self))
            return
        default:
            let error = DecodingError.Context(
                codingPath: discriminatorContainer.codingPath + [DiscriminatorCodingKeys.discriminator],
                debugDescription: """
                Failed to decode `SRShapeGradient`.
                Discriminator `type` did not match any known case.
                """
            )
            throw DecodingError.dataCorrupted(error)
        }
    }
}

@_spi(Internal)
public struct SRShapeGradientPoint: Codable, Hashable {
    /// Horizontal position, where 0 is the left edge and 1 is the right edge.
    public let x: Double

    /// Vertical position, where 0 is the top edge and 1 is the bottom edge.
    public let y: Double

    public enum CodingKeys: String, CodingKey {
        case x = "x"
        case y = "y"
    }

    ///
    /// - Parameters:
    ///   - x: Horizontal position, where 0 is the left edge and 1 is the right edge.
    ///   - y: Vertical position, where 0 is the top edge and 1 is the bottom edge.
    public init(
        x: Double,
        y: Double
    ) {
        self.x = x
        self.y = y
    }
}

/// A color and its relative position in a shape gradient.
@_spi(Internal)
public struct SRShapeGradientStop: Codable, Hashable {
    /// The stop color as a hexadecimal string in #RRGGBB or #RRGGBBAA format.
    public let color: String

    /// Relative stop position between 0 and 1. Stops must be ordered by non-decreasing position.
    public let position: Double

    public enum CodingKeys: String, CodingKey {
        case color = "color"
        case position = "position"
    }

    /// A color and its relative position in a shape gradient.
    ///
    /// - Parameters:
    ///   - color: The stop color as a hexadecimal string in #RRGGBB or #RRGGBBAA format.
    ///   - position: Relative stop position between 0 and 1. Stops must be ordered by non-decreasing position.
    public init(
        color: String,
        position: Double
    ) {
        self.color = color
        self.position = position
    }
}

/// A linear background gradient for a shape wireframe. Colors before the first stop and after the last stop are clamped to the nearest stop color.
@_spi(Internal)
public struct SRShapeLinearGradient: Codable, Hashable {
    /// The point where position 1 of the gradient is placed.
    public let endPoint: SRShapeGradientPoint

    /// The point where position 0 of the gradient is placed.
    public let startPoint: SRShapeGradientPoint

    /// Ordered gradient color stops. Positions must be non-decreasing.
    public let stops: [SRShapeGradientStop]

    /// The type of the gradient.
    public let type: String = "linear"

    public enum CodingKeys: String, CodingKey {
        case endPoint = "endPoint"
        case startPoint = "startPoint"
        case stops = "stops"
        case type = "type"
    }

    /// A linear background gradient for a shape wireframe. Colors before the first stop and after the last stop are clamped to the nearest stop color.
    ///
    /// - Parameters:
    ///   - endPoint: The point where position 1 of the gradient is placed.
    ///   - startPoint: The point where position 0 of the gradient is placed.
    ///   - stops: Ordered gradient color stops. Positions must be non-decreasing.
    public init(
        endPoint: SRShapeGradientPoint,
        startPoint: SRShapeGradientPoint,
        stops: [SRShapeGradientStop]
    ) {
        self.endPoint = endPoint
        self.startPoint = startPoint
        self.stops = stops
    }
}

/// The style of this wireframe.
@_spi(Internal)
public struct SRShapeStyle: Codable, Hashable {
    /// The background color for this wireframe as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional. The default value is #FFFFFF00.
    public let backgroundColor: String?

    /// The background gradient for this wireframe.
    public let backgroundGradient: SRShapeGradient?

    /// The corner(border) radius of this wireframe in pixels. The default value is 0.
    public let cornerRadius: Double?

    /// The opacity of this wireframe. Takes values from 0 to 1, default value is 1.
    public let opacity: Double?

    public enum CodingKeys: String, CodingKey {
        case backgroundColor = "backgroundColor"
        case backgroundGradient = "backgroundGradient"
        case cornerRadius = "cornerRadius"
        case opacity = "opacity"
    }

    /// The style of this wireframe.
    ///
    /// - Parameters:
    ///   - backgroundColor: The background color for this wireframe as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional. The default value is #FFFFFF00.
    ///   - backgroundGradient: The background gradient for this wireframe.
    ///   - cornerRadius: The corner(border) radius of this wireframe in pixels. The default value is 0.
    ///   - opacity: The opacity of this wireframe. Takes values from 0 to 1, default value is 1.
    public init(
        backgroundColor: String? = nil,
        backgroundGradient: SRShapeGradient? = nil,
        cornerRadius: Double? = nil,
        opacity: Double? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.backgroundGradient = backgroundGradient
        self.cornerRadius = cornerRadius
        self.opacity = opacity
    }
}

/// Schema of all properties of a ShapeWireframe.
@_spi(Internal)
public struct SRShapeWireframe: Codable, Hashable {
    /// The border properties of this wireframe. The default value is null (no-border).
    public let border: SRShapeBorder?

    /// Schema of clipping information for a Wireframe.
    public let clip: SRContentClip?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    public let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    public let id: Int64

    /// A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    public let permanentId: String?

    /// The style of this wireframe.
    public let shapeStyle: SRShapeStyle?

    /// The type of the wireframe.
    public let type: String = "shape"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    public let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let y: Int64

    public enum CodingKeys: String, CodingKey {
        case border = "border"
        case clip = "clip"
        case height = "height"
        case id = "id"
        case permanentId = "permanentId"
        case shapeStyle = "shapeStyle"
        case type = "type"
        case width = "width"
        case x = "x"
        case y = "y"
    }

    /// Schema of all properties of a ShapeWireframe.
    ///
    /// - Parameters:
    ///   - border: The border properties of this wireframe. The default value is null (no-border).
    ///   - clip: Schema of clipping information for a Wireframe.
    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    ///   - permanentId: A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    ///   - shapeStyle: The style of this wireframe.
    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public init(
        border: SRShapeBorder? = nil,
        clip: SRContentClip? = nil,
        height: Int64,
        id: Int64,
        permanentId: String? = nil,
        shapeStyle: SRShapeStyle? = nil,
        width: Int64,
        x: Int64,
        y: Int64
    ) {
        self.border = border
        self.clip = clip
        self.height = height
        self.id = id
        self.permanentId = permanentId
        self.shapeStyle = shapeStyle
        self.width = width
        self.x = x
        self.y = y
    }
}

/// Schema of all properties of a TextPosition.
@_spi(Internal)
public struct SRTextPosition: Codable, Hashable {
    public let alignment: Alignment?

    public let padding: Padding?

    public enum CodingKeys: String, CodingKey {
        case alignment = "alignment"
        case padding = "padding"
    }

    /// Schema of all properties of a TextPosition.
    ///
    /// - Parameters:
    ///   - alignment:
    ///   - padding:
    public init(
        alignment: Alignment? = nil,
        padding: Padding? = nil
    ) {
        self.alignment = alignment
        self.padding = padding
    }

    @_spi(Internal)
    public struct Alignment: Codable, Hashable {
        /// The horizontal text alignment. The default value is `left`.
        public let horizontal: Horizontal?

        /// The vertical text alignment. The default value is `top`.
        public let vertical: Vertical?

        public enum CodingKeys: String, CodingKey {
            case horizontal = "horizontal"
            case vertical = "vertical"
        }

        ///
        /// - Parameters:
        ///   - horizontal: The horizontal text alignment. The default value is `left`.
        ///   - vertical: The vertical text alignment. The default value is `top`.
        public init(
            horizontal: Horizontal? = nil,
            vertical: Vertical? = nil
        ) {
            self.horizontal = horizontal
            self.vertical = vertical
        }

        /// The horizontal text alignment. The default value is `left`.
        @_spi(Internal)
        public enum Horizontal: String, Codable {
            case left = "left"
            case right = "right"
            case center = "center"
        }

        /// The vertical text alignment. The default value is `top`.
        @_spi(Internal)
        public enum Vertical: String, Codable {
            case top = "top"
            case bottom = "bottom"
            case center = "center"
        }
    }

    @_spi(Internal)
    public struct Padding: Codable, Hashable {
        /// The bottom padding in pixels. The default value is 0.
        public let bottom: Int64?

        /// The left padding in pixels. The default value is 0.
        public let left: Int64?

        /// The right padding in pixels. The default value is 0.
        public let right: Int64?

        /// The top padding in pixels. The default value is 0.
        public let top: Int64?

        public enum CodingKeys: String, CodingKey {
            case bottom = "bottom"
            case left = "left"
            case right = "right"
            case top = "top"
        }

        ///
        /// - Parameters:
        ///   - bottom: The bottom padding in pixels. The default value is 0.
        ///   - left: The left padding in pixels. The default value is 0.
        ///   - right: The right padding in pixels. The default value is 0.
        ///   - top: The top padding in pixels. The default value is 0.
        public init(
            bottom: Int64? = nil,
            left: Int64? = nil,
            right: Int64? = nil,
            top: Int64? = nil
        ) {
            self.bottom = bottom
            self.left = left
            self.right = right
            self.top = top
        }
    }
}

/// Schema of all properties of a TextStyle.
@_spi(Internal)
public struct SRTextStyle: Codable, Hashable {
    /// The font color as a string hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
    public let color: String

    /// The preferred font family collection, ordered by preference and formatted as a String list: e.g. Century Gothic, Verdana, sans-serif
    public let family: String

    /// The font size in pixels.
    public let size: Int64

    /// Defines how text should be truncated when it exceeds the wireframe bounds. If omitted, text wraps naturally.
    public let truncationMode: TruncationMode?

    public enum CodingKeys: String, CodingKey {
        case color = "color"
        case family = "family"
        case size = "size"
        case truncationMode = "truncationMode"
    }

    /// Schema of all properties of a TextStyle.
    ///
    /// - Parameters:
    ///   - color: The font color as a string hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
    ///   - family: The preferred font family collection, ordered by preference and formatted as a String list: e.g. Century Gothic, Verdana, sans-serif
    ///   - size: The font size in pixels.
    ///   - truncationMode: Defines how text should be truncated when it exceeds the wireframe bounds. If omitted, text wraps naturally.
    public init(
        color: String,
        family: String,
        size: Int64,
        truncationMode: TruncationMode? = nil
    ) {
        self.color = color
        self.family = family
        self.size = size
        self.truncationMode = truncationMode
    }

    /// Defines how text should be truncated when it exceeds the wireframe bounds. If omitted, text wraps naturally.
    @_spi(Internal)
    public enum TruncationMode: String, Codable {
        case clip = "clip"
        case head = "head"
        case tail = "tail"
        case middle = "middle"
    }
}

/// Schema of all properties of a TextWireframe.
@_spi(Internal)
public struct SRTextWireframe: Codable, Hashable {
    /// The border properties of this wireframe. The default value is null (no-border).
    public let border: SRShapeBorder?

    /// Schema of clipping information for a Wireframe.
    public let clip: SRContentClip?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    public let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    public let id: Int64

    /// A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    public let permanentId: String?

    /// The style of this wireframe.
    public let shapeStyle: SRShapeStyle?

    /// The text value of the wireframe.
    public var text: String

    /// Schema of all properties of a TextPosition.
    public let textPosition: SRTextPosition?

    /// Schema of all properties of a TextStyle.
    public let textStyle: SRTextStyle

    /// The type of the wireframe.
    public let type: String = "text"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    public let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let y: Int64

    public enum CodingKeys: String, CodingKey {
        case border = "border"
        case clip = "clip"
        case height = "height"
        case id = "id"
        case permanentId = "permanentId"
        case shapeStyle = "shapeStyle"
        case text = "text"
        case textPosition = "textPosition"
        case textStyle = "textStyle"
        case type = "type"
        case width = "width"
        case x = "x"
        case y = "y"
    }

    /// Schema of all properties of a TextWireframe.
    ///
    /// - Parameters:
    ///   - border: The border properties of this wireframe. The default value is null (no-border).
    ///   - clip: Schema of clipping information for a Wireframe.
    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    ///   - permanentId: A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    ///   - shapeStyle: The style of this wireframe.
    ///   - text: The text value of the wireframe.
    ///   - textPosition: Schema of all properties of a TextPosition.
    ///   - textStyle: Schema of all properties of a TextStyle.
    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public init(
        border: SRShapeBorder? = nil,
        clip: SRContentClip? = nil,
        height: Int64,
        id: Int64,
        permanentId: String? = nil,
        shapeStyle: SRShapeStyle? = nil,
        text: String,
        textPosition: SRTextPosition? = nil,
        textStyle: SRTextStyle,
        width: Int64,
        x: Int64,
        y: Int64
    ) {
        self.border = border
        self.clip = clip
        self.height = height
        self.id = id
        self.permanentId = permanentId
        self.shapeStyle = shapeStyle
        self.text = text
        self.textPosition = textPosition
        self.textStyle = textStyle
        self.width = width
        self.x = x
        self.y = y
    }
}

/// Schema of a Record which signifies that view lifecycle ended.
@_spi(Internal)
public struct SRViewEndRecord: Codable {
    /// Unique ID of the slot that generated this record.
    public let slotId: String?

    /// Defines the UTC time in milliseconds when this Record was performed.
    public let timestamp: Int64

    /// The type of this Record.
    public let type: Int64 = 7

    public enum CodingKeys: String, CodingKey {
        case slotId = "slotId"
        case timestamp = "timestamp"
        case type = "type"
    }

    /// Schema of a Record which signifies that view lifecycle ended.
    ///
    /// - Parameters:
    ///   - slotId: Unique ID of the slot that generated this record.
    ///   - timestamp: Defines the UTC time in milliseconds when this Record was performed.
    public init(
        slotId: String? = nil,
        timestamp: Int64
    ) {
        self.slotId = slotId
        self.timestamp = timestamp
    }
}

/// Schema of a Record which signifies that the viewport properties have changed.
@_spi(Internal)
public struct SRVisualViewportRecord: Codable {
    public let data: Data

    /// Unique ID of the slot that generated this record.
    public let slotId: String?

    /// Defines the UTC time in milliseconds when this Record was performed.
    public let timestamp: Int64

    /// The type of this Record.
    public let type: Int64 = 8

    public enum CodingKeys: String, CodingKey {
        case data = "data"
        case slotId = "slotId"
        case timestamp = "timestamp"
        case type = "type"
    }

    /// Schema of a Record which signifies that the viewport properties have changed.
    ///
    /// - Parameters:
    ///   - data:
    ///   - slotId: Unique ID of the slot that generated this record.
    ///   - timestamp: Defines the UTC time in milliseconds when this Record was performed.
    public init(
        data: Data,
        slotId: String? = nil,
        timestamp: Int64
    ) {
        self.data = data
        self.slotId = slotId
        self.timestamp = timestamp
    }

    @_spi(Internal)
    public struct Data: Codable {
        public let height: Double

        public let offsetLeft: Double

        public let offsetTop: Double

        public let pageLeft: Double

        public let pageTop: Double

        public let scale: Double

        public let width: Double

        public enum CodingKeys: String, CodingKey {
            case height = "height"
            case offsetLeft = "offsetLeft"
            case offsetTop = "offsetTop"
            case pageLeft = "pageLeft"
            case pageTop = "pageTop"
            case scale = "scale"
            case width = "width"
        }

        ///
        /// - Parameters:
        ///   - height:
        ///   - offsetLeft:
        ///   - offsetTop:
        ///   - pageLeft:
        ///   - pageTop:
        ///   - scale:
        ///   - width:
        public init(
            height: Double,
            offsetLeft: Double,
            offsetTop: Double,
            pageLeft: Double,
            pageTop: Double,
            scale: Double,
            width: Double
        ) {
            self.height = height
            self.offsetLeft = offsetLeft
            self.offsetTop = offsetTop
            self.pageLeft = pageLeft
            self.pageTop = pageTop
            self.scale = scale
            self.width = width
        }
    }
}

/// Schema of all properties of a WebviewWireframe.
@_spi(Internal)
public struct SRWebviewWireframe: Codable, Hashable {
    /// The border properties of this wireframe. The default value is null (no-border).
    public let border: SRShapeBorder?

    /// Schema of clipping information for a Wireframe.
    public let clip: SRContentClip?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    public let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    public let id: Int64

    /// Whether this webview is visible or not.
    public let isVisible: Bool?

    /// A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    public let permanentId: String?

    /// The style of this wireframe.
    public let shapeStyle: SRShapeStyle?

    /// Unique Id of the slot containing this webview.
    public let slotId: String

    /// The type of the wireframe.
    public let type: String = "webview"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    public let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public let y: Int64

    public enum CodingKeys: String, CodingKey {
        case border = "border"
        case clip = "clip"
        case height = "height"
        case id = "id"
        case isVisible = "isVisible"
        case permanentId = "permanentId"
        case shapeStyle = "shapeStyle"
        case slotId = "slotId"
        case type = "type"
        case width = "width"
        case x = "x"
        case y = "y"
    }

    /// Schema of all properties of a WebviewWireframe.
    ///
    /// - Parameters:
    ///   - border: The border properties of this wireframe. The default value is null (no-border).
    ///   - clip: Schema of clipping information for a Wireframe.
    ///   - height: The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    ///   - id: Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    ///   - isVisible: Whether this webview is visible or not.
    ///   - permanentId: A globally unique and stable identifier for this UI element, computed as the hash of the element's path. Used to correlate wireframes with RUM action events.
    ///   - shapeStyle: The style of this wireframe.
    ///   - slotId: Unique Id of the slot containing this webview.
    ///   - width: The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    ///   - x: The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    ///   - y: The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    public init(
        border: SRShapeBorder? = nil,
        clip: SRContentClip? = nil,
        height: Int64,
        id: Int64,
        isVisible: Bool? = nil,
        permanentId: String? = nil,
        shapeStyle: SRShapeStyle? = nil,
        slotId: String,
        width: Int64,
        x: Int64,
        y: Int64
    ) {
        self.border = border
        self.clip = clip
        self.height = height
        self.id = id
        self.isVisible = isVisible
        self.permanentId = permanentId
        self.shapeStyle = shapeStyle
        self.slotId = slotId
        self.width = width
        self.x = x
        self.y = y
    }
}

/// Schema of a Wireframe type.
@_spi(Internal)
public enum SRWireframe: Codable {
    case shapeWireframe(value: SRShapeWireframe)
    case textWireframe(value: SRTextWireframe)
    case imageWireframe(value: SRImageWireframe)
    case placeholderWireframe(value: SRPlaceholderWireframe)
    case webviewWireframe(value: SRWebviewWireframe)
    case embeddedContentWireframe(value: SREmbeddedContentWireframe)

    private enum DiscriminatorCodingKeys: String, CodingKey {
        case discriminator = "type"
    }

    // MARK: - Codable

    public func encode(to encoder: Encoder) throws {
        // Encode only the associated value, without encoding enum case
        var container = encoder.singleValueContainer()

        switch self {
        case .shapeWireframe(let value):
            try container.encode(value)
        case .textWireframe(let value):
            try container.encode(value)
        case .imageWireframe(let value):
            try container.encode(value)
        case .placeholderWireframe(let value):
            try container.encode(value)
        case .webviewWireframe(let value):
            try container.encode(value)
        case .embeddedContentWireframe(let value):
            try container.encode(value)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode enum case from discriminator
        let container = try decoder.singleValueContainer()
        let discriminatorContainer = try decoder.container(keyedBy: DiscriminatorCodingKeys.self)

        switch try discriminatorContainer.decode(String.self, forKey: .discriminator) {
        case "shape":
            self = .shapeWireframe(value: try container.decode(SRShapeWireframe.self))
            return
        case "text":
            self = .textWireframe(value: try container.decode(SRTextWireframe.self))
            return
        case "image":
            self = .imageWireframe(value: try container.decode(SRImageWireframe.self))
            return
        case "placeholder":
            self = .placeholderWireframe(value: try container.decode(SRPlaceholderWireframe.self))
            return
        case "webview":
            self = .webviewWireframe(value: try container.decode(SRWebviewWireframe.self))
            return
        case "embedded_content":
            self = .embeddedContentWireframe(value: try container.decode(SREmbeddedContentWireframe.self))
            return
        default:
            let error = DecodingError.Context(
                codingPath: discriminatorContainer.codingPath + [DiscriminatorCodingKeys.discriminator],
                debugDescription: """
                Failed to decode `SRWireframe`.
                Discriminator `type` did not match any known case.
                """
            )
            throw DecodingError.dataCorrupted(error)
        }
    }
}
#endif
// Generated from https://github.com/DataDog/rum-events-format/tree/7cd262a46caa5a3927eda082757eb30673f2b5aa
