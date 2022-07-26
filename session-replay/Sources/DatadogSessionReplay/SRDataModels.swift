/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

// This file was generated from JSON Schema. Do not modify it directly.

internal protocol SRDataModel: Codable {}

/// Mobile-specific. Schema of a Session Replay data Segment.
internal struct SRMobileSegment: SRDataModel {
    /// Application properties
    internal let application: Application

    /// The end UTC timestamp in milliseconds corresponding to the last record in the Segment data. Each timestamp is computed as the UTC interval since 00:00:00.000 01.01.1970.
    internal let end: Int64

    /// Whether this Segment contains a full snapshot record or not.
    internal let hasFullSnapshot: Bool?

    /// The index of this Segment in the segments list that was recorded for this view ID. Starts from 0.
    internal let indexInView: Int64

    /// The records contained by this Segment.
    internal let records: [Records]

    /// The number of records in this Segment.
    internal let recordsCount: Int64

    /// Session properties
    internal let session: Session

    /// The source of this record
    internal let source: Source

    /// The start UTC timestamp in milliseconds corresponding to the first record in the Segment data. Each timestamp is computed as the UTC interval since 00:00:00.000 01.01.1970.
    internal let start: Int64

    /// View properties
    internal let view: View

    enum CodingKeys: String, CodingKey {
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

    /// Application properties
    internal struct Application: Codable {
        /// UUID of the application
        internal let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Mobile-specific. Schema of a Session Replay Record.
    internal enum Records: Codable {
        case mobileFullSnapshotRecord(value: SRMobileFullSnapshotRecord)
        case mobileIncrementalSnapshotRecord(value: SRMobileIncrementalSnapshotRecord)
        case metaRecord(value: SRMetaRecord)
        case focusRecord(value: SRFocusRecord)
        case viewEndRecord(value: SRViewEndRecord)
        case visualViewportRecord(value: SRVisualViewportRecord)

        // MARK: - Codable

        internal func encode(to encoder: Encoder) throws {
            // Encode only the associated value, without encoding enum case
            var container = encoder.singleValueContainer()

            switch self {
            case .mobileFullSnapshotRecord(let value):
                try container.encode(value)
            case .mobileIncrementalSnapshotRecord(let value):
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

        internal init(from decoder: Decoder) throws {
            // Decode enum case from associated value
            let container = try decoder.singleValueContainer()

            if let value = try? container.decode(SRMobileFullSnapshotRecord.self) {
                self = .mobileFullSnapshotRecord(value: value)
                return
            }
            if let value = try? container.decode(SRMobileIncrementalSnapshotRecord.self) {
                self = .mobileIncrementalSnapshotRecord(value: value)
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
                Failed to decode `Records`.
                Ran out of possibilities when trying to decode the value of associated type.
                """
            )
            throw DecodingError.typeMismatch(Records.self, error)
        }
    }

    /// Session properties
    internal struct Session: Codable {
        /// UUID of the session
        internal let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// The source of this record
    internal enum Source: String, Codable {
        case android = "android"
        case ios = "ios"
        case flutter = "flutter"
        case reactNative = "react-native"
    }

    /// View properties
    internal struct View: Codable {
        /// UUID of the view
        internal let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }
}

/// Schema of all properties of a ShapeWireframe.
internal struct SRShapeWireframe: Codable {
    /// The border properties of this wireframe. The default value is null (no-border).
    internal let border: Border?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    internal let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    internal let id: Int64

    /// The style of this wireframe.
    internal let shapeStyle: ShapeStyle?

    /// The type of the wireframe.
    internal let type: String = "shape"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    internal let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    internal let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    internal let y: Int64

    enum CodingKeys: String, CodingKey {
        case border = "border"
        case height = "height"
        case id = "id"
        case shapeStyle = "shapeStyle"
        case type = "type"
        case width = "width"
        case x = "x"
        case y = "y"
    }

    /// The border properties of this wireframe. The default value is null (no-border).
    internal struct Border: Codable {
        /// The border color as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
        internal let color: String

        /// The width of the border in pixels.
        internal let width: Int64

        enum CodingKeys: String, CodingKey {
            case color = "color"
            case width = "width"
        }
    }

    /// The style of this wireframe.
    internal struct ShapeStyle: Codable {
        /// The background color for this wireframe as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional. The default value is #FFFFFF00.
        internal let backgroundColor: String?

        /// The corner(border) radius of this wireframe in pixels. The default value is 0.
        internal let cornerRadius: Double?

        /// The opacity of this wireframe. Takes values from 0 to 1, default value is 1.
        internal let opacity: Double?

        enum CodingKeys: String, CodingKey {
            case backgroundColor = "backgroundColor"
            case cornerRadius = "cornerRadius"
            case opacity = "opacity"
        }
    }
}

/// Schema of all properties of a TextWireframe.
internal struct SRTextWireframe: Codable {
    /// The border properties of this wireframe. The default value is null (no-border).
    internal let border: Border?

    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
    internal let height: Int64

    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
    internal let id: Int64

    /// The style of this wireframe.
    internal let shapeStyle: ShapeStyle?

    /// The text value of the wireframe.
    internal var text: String

    /// Schema of all properties of a TextPosition.
    internal let textPosition: TextPosition?

    /// Schema of all properties of a TextStyle.
    internal let textStyle: TextStyle

    /// The type of the wireframe.
    internal let type: String = "text"

    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
    internal let width: Int64

    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    internal let x: Int64

    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
    internal let y: Int64

    enum CodingKeys: String, CodingKey {
        case border = "border"
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

    /// The border properties of this wireframe. The default value is null (no-border).
    internal struct Border: Codable {
        /// The border color as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
        internal let color: String

        /// The width of the border in pixels.
        internal let width: Int64

        enum CodingKeys: String, CodingKey {
            case color = "color"
            case width = "width"
        }
    }

    /// The style of this wireframe.
    internal struct ShapeStyle: Codable {
        /// The background color for this wireframe as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional. The default value is #FFFFFF00.
        internal let backgroundColor: String?

        /// The corner(border) radius of this wireframe in pixels. The default value is 0.
        internal let cornerRadius: Double?

        /// The opacity of this wireframe. Takes values from 0 to 1, default value is 1.
        internal let opacity: Double?

        enum CodingKeys: String, CodingKey {
            case backgroundColor = "backgroundColor"
            case cornerRadius = "cornerRadius"
            case opacity = "opacity"
        }
    }

    /// Schema of all properties of a TextPosition.
    internal struct TextPosition: Codable {
        internal let alignment: Alignment?

        internal let padding: Padding?

        enum CodingKeys: String, CodingKey {
            case alignment = "alignment"
            case padding = "padding"
        }

        internal struct Alignment: Codable {
            /// The horizontal text alignment. The default value is `left`.
            internal let horizontal: Horizontal?

            /// The vertical text alignment. The default value is `top`.
            internal let vertical: Vertical?

            enum CodingKeys: String, CodingKey {
                case horizontal = "horizontal"
                case vertical = "vertical"
            }

            /// The horizontal text alignment. The default value is `left`.
            internal enum Horizontal: String, Codable {
                case left = "left"
                case right = "right"
                case center = "center"
            }

            /// The vertical text alignment. The default value is `top`.
            internal enum Vertical: String, Codable {
                case top = "top"
                case bottom = "bottom"
                case center = "center"
            }
        }

        internal struct Padding: Codable {
            /// The bottom padding in pixels. The default value is 0.
            internal let bottom: Int64?

            /// The left padding in pixels. The default value is 0.
            internal let left: Int64?

            /// The right padding in pixels. The default value is 0.
            internal let right: Int64?

            /// The top padding in pixels. The default value is 0.
            internal let top: Int64?

            enum CodingKeys: String, CodingKey {
                case bottom = "bottom"
                case left = "left"
                case right = "right"
                case top = "top"
            }
        }
    }

    /// Schema of all properties of a TextStyle.
    internal struct TextStyle: Codable {
        /// The font color as a string hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
        internal let color: String

        /// The font family.
        internal let family: String

        /// The font size in pixels.
        internal let size: Int64

        /// The font type.
        internal let type: TextStyleType

        enum CodingKeys: String, CodingKey {
            case color = "color"
            case family = "family"
            case size = "size"
            case type = "type"
        }

        /// The font type.
        internal enum TextStyleType: String, Codable {
            case serif = "serif"
            case sansSerif = "sans-serif"
            case script = "script"
            case monospaced = "monospaced"
            case dynamic = "dynamic"
        }
    }
}

/// Mobile-specific. Schema of a Record type which contains the full snapshot of a screen.
internal struct SRMobileFullSnapshotRecord: Codable {
    internal let data: Data

    /// Defines the UTC time in milliseconds when this Record was performed.
    internal let timestamp: Int64

    /// The type of this Record.
    internal let type: Int64 = 2

    enum CodingKeys: String, CodingKey {
        case data = "data"
        case timestamp = "timestamp"
        case type = "type"
    }

    internal struct Data: Codable {
        /// The Wireframes contained by this Record.
        internal let wireframes: [Wireframes]

        enum CodingKeys: String, CodingKey {
            case wireframes = "wireframes"
        }

        /// Schema of a Wireframe type.
        internal enum Wireframes: Codable {
            case shapeWireframe(value: SRShapeWireframe)
            case textWireframe(value: SRTextWireframe)

            // MARK: - Codable

            internal func encode(to encoder: Encoder) throws {
                // Encode only the associated value, without encoding enum case
                var container = encoder.singleValueContainer()

                switch self {
                case .shapeWireframe(let value):
                    try container.encode(value)
                case .textWireframe(let value):
                    try container.encode(value)
                }
            }

            internal init(from decoder: Decoder) throws {
                // Decode enum case from associated value
                let container = try decoder.singleValueContainer()

                if let value = try? container.decode(SRShapeWireframe.self) {
                    self = .shapeWireframe(value: value)
                    return
                }
                if let value = try? container.decode(SRTextWireframe.self) {
                    self = .textWireframe(value: value)
                    return
                }
                let error = DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: """
                    Failed to decode `Wireframes`.
                    Ran out of possibilities when trying to decode the value of associated type.
                    """
                )
                throw DecodingError.typeMismatch(Wireframes.self, error)
            }
        }
    }
}

/// Mobile-specific. Schema of a Record type which contains mutations of a screen.
internal struct SRMobileIncrementalSnapshotRecord: Codable {
    /// Mobile-specific. Schema of a Session Replay IncrementalData type.
    internal let data: Data

    /// Defines the UTC time in milliseconds when this Record was performed.
    internal let timestamp: Int64

    /// The type of this Record.
    internal let type: Int64 = 3

    enum CodingKeys: String, CodingKey {
        case data = "data"
        case timestamp = "timestamp"
        case type = "type"
    }

    /// Mobile-specific. Schema of a Session Replay IncrementalData type.
    internal enum Data: Codable {
        case mobileMutationData(value: MobileMutationData)
        case touchData(value: TouchData)
        case viewportResizeData(value: ViewportResizeData)

        // MARK: - Codable

        internal func encode(to encoder: Encoder) throws {
            // Encode only the associated value, without encoding enum case
            var container = encoder.singleValueContainer()

            switch self {
            case .mobileMutationData(let value):
                try container.encode(value)
            case .touchData(let value):
                try container.encode(value)
            case .viewportResizeData(let value):
                try container.encode(value)
            }
        }

        internal init(from decoder: Decoder) throws {
            // Decode enum case from associated value
            let container = try decoder.singleValueContainer()

            if let value = try? container.decode(MobileMutationData.self) {
                self = .mobileMutationData(value: value)
                return
            }
            if let value = try? container.decode(TouchData.self) {
                self = .touchData(value: value)
                return
            }
            if let value = try? container.decode(ViewportResizeData.self) {
                self = .viewportResizeData(value: value)
                return
            }
            let error = DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: """
                Failed to decode `Data`.
                Ran out of possibilities when trying to decode the value of associated type.
                """
            )
            throw DecodingError.typeMismatch(Data.self, error)
        }

        /// Mobile-specific. Schema of a MutationData.
        internal struct MobileMutationData: Codable {
            /// Contains the newly added wireframes.
            internal let adds: [Adds]

            /// Contains the removed wireframes as an array of ids.
            internal let removes: [Removes]

            /// The source of this type of incremental data.
            internal let source: Int64? = 0

            /// Contains the updated wireframes mutations.
            internal let updates: [Updates]

            enum CodingKeys: String, CodingKey {
                case adds = "adds"
                case removes = "removes"
                case source = "source"
                case updates = "updates"
            }

            internal struct Adds: Codable {
                /// The previous wireframe id next or after which this new wireframe is drawn or attached to, respectively.
                internal let previousId: Int64?

                /// Schema of a Wireframe type.
                internal let wireframe: Wireframe

                enum CodingKeys: String, CodingKey {
                    case previousId = "previousId"
                    case wireframe = "wireframe"
                }

                /// Schema of a Wireframe type.
                internal enum Wireframe: Codable {
                    case shapeWireframe(value: SRShapeWireframe)
                    case textWireframe(value: SRTextWireframe)

                    // MARK: - Codable

                    internal func encode(to encoder: Encoder) throws {
                        // Encode only the associated value, without encoding enum case
                        var container = encoder.singleValueContainer()

                        switch self {
                        case .shapeWireframe(let value):
                            try container.encode(value)
                        case .textWireframe(let value):
                            try container.encode(value)
                        }
                    }

                    internal init(from decoder: Decoder) throws {
                        // Decode enum case from associated value
                        let container = try decoder.singleValueContainer()

                        if let value = try? container.decode(SRShapeWireframe.self) {
                            self = .shapeWireframe(value: value)
                            return
                        }
                        if let value = try? container.decode(SRTextWireframe.self) {
                            self = .textWireframe(value: value)
                            return
                        }
                        let error = DecodingError.Context(
                            codingPath: container.codingPath,
                            debugDescription: """
                            Failed to decode `Wireframe`.
                            Ran out of possibilities when trying to decode the value of associated type.
                            """
                        )
                        throw DecodingError.typeMismatch(Wireframe.self, error)
                    }
                }
            }

            internal struct Removes: Codable {
                /// The id of the wireframe that needs to be removed.
                internal let id: Int64

                enum CodingKeys: String, CodingKey {
                    case id = "id"
                }
            }

            /// Schema of a WireframeUpdateMutation type.
            internal enum Updates: Codable {
                case textWireframeUpdate(value: TextWireframeUpdate)
                case shapeWireframeUpdate(value: ShapeWireframeUpdate)

                // MARK: - Codable

                internal func encode(to encoder: Encoder) throws {
                    // Encode only the associated value, without encoding enum case
                    var container = encoder.singleValueContainer()

                    switch self {
                    case .textWireframeUpdate(let value):
                        try container.encode(value)
                    case .shapeWireframeUpdate(let value):
                        try container.encode(value)
                    }
                }

                internal init(from decoder: Decoder) throws {
                    // Decode enum case from associated value
                    let container = try decoder.singleValueContainer()

                    if let value = try? container.decode(TextWireframeUpdate.self) {
                        self = .textWireframeUpdate(value: value)
                        return
                    }
                    if let value = try? container.decode(ShapeWireframeUpdate.self) {
                        self = .shapeWireframeUpdate(value: value)
                        return
                    }
                    let error = DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: """
                        Failed to decode `Updates`.
                        Ran out of possibilities when trying to decode the value of associated type.
                        """
                    )
                    throw DecodingError.typeMismatch(Updates.self, error)
                }

                /// Schema of all properties of a TextWireframeUpdate.
                internal struct TextWireframeUpdate: Codable {
                    /// The border properties of this wireframe. The default value is null (no-border).
                    internal let border: Border?

                    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    internal let height: Int64?

                    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    internal let id: Int64

                    /// The style of this wireframe.
                    internal let shapeStyle: ShapeStyle?

                    /// The text value of the wireframe.
                    internal var text: String?

                    /// Schema of all properties of a TextPosition.
                    internal let textPosition: TextPosition?

                    /// Schema of all properties of a TextStyle.
                    internal let textStyle: TextStyle?

                    /// The type of the wireframe.
                    internal let type: String = "text"

                    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    internal let width: Int64?

                    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    internal let x: Int64?

                    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    internal let y: Int64?

                    enum CodingKeys: String, CodingKey {
                        case border = "border"
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

                    /// The border properties of this wireframe. The default value is null (no-border).
                    internal struct Border: Codable {
                        /// The border color as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
                        internal let color: String

                        /// The width of the border in pixels.
                        internal let width: Int64

                        enum CodingKeys: String, CodingKey {
                            case color = "color"
                            case width = "width"
                        }
                    }

                    /// The style of this wireframe.
                    internal struct ShapeStyle: Codable {
                        /// The background color for this wireframe as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional. The default value is #FFFFFF00.
                        internal let backgroundColor: String?

                        /// The corner(border) radius of this wireframe in pixels. The default value is 0.
                        internal let cornerRadius: Double?

                        /// The opacity of this wireframe. Takes values from 0 to 1, default value is 1.
                        internal let opacity: Double?

                        enum CodingKeys: String, CodingKey {
                            case backgroundColor = "backgroundColor"
                            case cornerRadius = "cornerRadius"
                            case opacity = "opacity"
                        }
                    }

                    /// Schema of all properties of a TextPosition.
                    internal struct TextPosition: Codable {
                        internal let alignment: Alignment?

                        internal let padding: Padding?

                        enum CodingKeys: String, CodingKey {
                            case alignment = "alignment"
                            case padding = "padding"
                        }

                        internal struct Alignment: Codable {
                            /// The horizontal text alignment. The default value is `left`.
                            internal let horizontal: Horizontal?

                            /// The vertical text alignment. The default value is `top`.
                            internal let vertical: Vertical?

                            enum CodingKeys: String, CodingKey {
                                case horizontal = "horizontal"
                                case vertical = "vertical"
                            }

                            /// The horizontal text alignment. The default value is `left`.
                            internal enum Horizontal: String, Codable {
                                case left = "left"
                                case right = "right"
                                case center = "center"
                            }

                            /// The vertical text alignment. The default value is `top`.
                            internal enum Vertical: String, Codable {
                                case top = "top"
                                case bottom = "bottom"
                                case center = "center"
                            }
                        }

                        internal struct Padding: Codable {
                            /// The bottom padding in pixels. The default value is 0.
                            internal let bottom: Int64?

                            /// The left padding in pixels. The default value is 0.
                            internal let left: Int64?

                            /// The right padding in pixels. The default value is 0.
                            internal let right: Int64?

                            /// The top padding in pixels. The default value is 0.
                            internal let top: Int64?

                            enum CodingKeys: String, CodingKey {
                                case bottom = "bottom"
                                case left = "left"
                                case right = "right"
                                case top = "top"
                            }
                        }
                    }

                    /// Schema of all properties of a TextStyle.
                    internal struct TextStyle: Codable {
                        /// The font color as a string hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
                        internal let color: String

                        /// The font family.
                        internal let family: String

                        /// The font size in pixels.
                        internal let size: Int64

                        /// The font type.
                        internal let type: TextStyleType

                        enum CodingKeys: String, CodingKey {
                            case color = "color"
                            case family = "family"
                            case size = "size"
                            case type = "type"
                        }

                        /// The font type.
                        internal enum TextStyleType: String, Codable {
                            case serif = "serif"
                            case sansSerif = "sans-serif"
                            case script = "script"
                            case monospaced = "monospaced"
                            case dynamic = "dynamic"
                        }
                    }
                }

                /// Schema of a ShapeWireframeUpdate.
                internal struct ShapeWireframeUpdate: Codable {
                    /// The border properties of this wireframe. The default value is null (no-border).
                    internal let border: Border?

                    /// The height in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height of all UI elements is divided by 2 to get a normalized height.
                    internal let height: Int64?

                    /// Defines the unique ID of the wireframe. This is persistent throughout the view lifetime.
                    internal let id: Int64

                    /// The style of this wireframe.
                    internal let shapeStyle: ShapeStyle?

                    /// The type of the wireframe.
                    internal let type: String = "shape"

                    /// The width in pixels of the UI element, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width of all UI elements is divided by 2 to get a normalized width.
                    internal let width: Int64?

                    /// The position in pixels on X axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    internal let x: Int64?

                    /// The position in pixels on Y axis of the UI element in absolute coordinates. The anchor point is always the top-left corner of the wireframe.
                    internal let y: Int64?

                    enum CodingKeys: String, CodingKey {
                        case border = "border"
                        case height = "height"
                        case id = "id"
                        case shapeStyle = "shapeStyle"
                        case type = "type"
                        case width = "width"
                        case x = "x"
                        case y = "y"
                    }

                    /// The border properties of this wireframe. The default value is null (no-border).
                    internal struct Border: Codable {
                        /// The border color as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional.
                        internal let color: String

                        /// The width of the border in pixels.
                        internal let width: Int64

                        enum CodingKeys: String, CodingKey {
                            case color = "color"
                            case width = "width"
                        }
                    }

                    /// The style of this wireframe.
                    internal struct ShapeStyle: Codable {
                        /// The background color for this wireframe as a String hexadecimal. Follows the #RRGGBBAA color format with the alpha value as optional. The default value is #FFFFFF00.
                        internal let backgroundColor: String?

                        /// The corner(border) radius of this wireframe in pixels. The default value is 0.
                        internal let cornerRadius: Double?

                        /// The opacity of this wireframe. Takes values from 0 to 1, default value is 1.
                        internal let opacity: Double?

                        enum CodingKeys: String, CodingKey {
                            case backgroundColor = "backgroundColor"
                            case cornerRadius = "cornerRadius"
                            case opacity = "opacity"
                        }
                    }
                }
            }
        }

        /// Schema of a TouchData.
        internal struct TouchData: Codable {
            /// Contains the positions of the finger on the screen during the touchDown/touchUp event lifecycle.
            internal let positions: [Positions]?

            /// The source of this type of incremental data.
            internal let source: Int64? = 2

            enum CodingKeys: String, CodingKey {
                case positions = "positions"
                case source = "source"
            }

            internal struct Positions: Codable {
                /// The touch id of the touch event this position corresponds to. In mobile it is possible to have multiple touch events (fingers touching the screen) happening at the same time.
                internal let id: Int64

                /// The UTC timestamp in milliseconds corresponding to the moment the position change was recorded. Each timestamp is computed as the UTC interval since 00:00:00.000 01.01.1970.
                internal let timestamp: Int64

                /// The x coordinate value of the position.
                internal let x: Int64

                /// The y coordinate value of the position.
                internal let y: Int64

                enum CodingKeys: String, CodingKey {
                    case id = "id"
                    case timestamp = "timestamp"
                    case x = "x"
                    case y = "y"
                }
            }
        }

        /// Schema of a ViewportResizeData.
        internal struct ViewportResizeData: Codable {
            /// The new height of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the height is divided by 2 to get a normalized height.
            internal let height: Int64

            /// The source of this type of incremental data.
            internal let source: Int64 = 4

            /// The new width of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the width is divided by 2 to get a normalized width.
            internal let width: Int64

            enum CodingKeys: String, CodingKey {
                case height = "height"
                case source = "source"
                case width = "width"
            }
        }
    }
}

/// Schema of a Record which contains the screen properties.
internal struct SRMetaRecord: Codable {
    /// The data contained by this record.
    internal let data: Data

    /// Defines the UTC time in milliseconds when this Record was performed.
    internal let timestamp: Int64

    /// The type of this Record.
    internal let type: Int64 = 4

    enum CodingKeys: String, CodingKey {
        case data = "data"
        case timestamp = "timestamp"
        case type = "type"
    }

    /// The data contained by this record.
    internal struct Data: Codable {
        /// The height of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the normalized height is the current height divided by 2.
        internal let height: Int64

        /// Browser-specific. URL of the view described by this record.
        internal let href: String?

        /// The width of the screen in pixels, normalized based on the device pixels per inch density (DPI). Example: if a device has a DPI = 2, the normalized width is the current width divided by 2.
        internal let width: Int64

        enum CodingKeys: String, CodingKey {
            case height = "height"
            case href = "href"
            case width = "width"
        }
    }
}

/// Schema of a Record type which contains focus information.
internal struct SRFocusRecord: Codable {
    internal let data: Data

    /// Defines the UTC time in milliseconds when this Record was performed.
    internal let timestamp: Int64

    /// The type of this Record.
    internal let type: Int64 = 6

    enum CodingKeys: String, CodingKey {
        case data = "data"
        case timestamp = "timestamp"
        case type = "type"
    }

    internal struct Data: Codable {
        /// Whether this screen has a focus or not. For now it will always be true for mobile.
        internal let hasFocus: Bool

        enum CodingKeys: String, CodingKey {
            case hasFocus = "has_focus"
        }
    }
}

/// Schema of a Record which signifies that view lifecycle ended.
internal struct SRViewEndRecord: Codable {
    /// Defines the UTC time in milliseconds when this Record was performed.
    internal let timestamp: Int64

    /// The type of this Record.
    internal let type: Int64 = 7

    enum CodingKeys: String, CodingKey {
        case timestamp = "timestamp"
        case type = "type"
    }
}

/// Schema of a Record which signifies that the viewport properties have changed.
internal struct SRVisualViewportRecord: Codable {
    internal let data: Data

    /// Defines the UTC time in milliseconds when this Record was performed.
    internal let timestamp: Int64

    /// The type of this Record.
    internal let type: Int64 = 8

    enum CodingKeys: String, CodingKey {
        case data = "data"
        case timestamp = "timestamp"
        case type = "type"
    }

    internal struct Data: Codable {
        internal let height: Double

        internal let offsetLeft: Double

        internal let offsetTop: Double

        internal let pageLeft: Double

        internal let pageTop: Double

        internal let scale: Double

        internal let width: Double

        enum CodingKeys: String, CodingKey {
            case height = "height"
            case offsetLeft = "offsetLeft"
            case offsetTop = "offsetTop"
            case pageLeft = "pageLeft"
            case pageTop = "pageTop"
            case scale = "scale"
            case width = "width"
        }
    }
}
