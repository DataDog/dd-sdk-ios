/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import DatadogSessionReplay

extension SRTextWireframe: AnyMockable, RandomMockable {
    static func mockAny() -> SRTextWireframe {
        return .mockWith()
    }

    static func mockRandom() -> SRTextWireframe {
        return .mockRandomWith(id: .mockRandom())
    }

    static func mockRandomWith(id: WireframeID) -> SRTextWireframe {
        return SRTextWireframe(
            border: .mockRandom(),
            height: .mockRandom(),
            id: id,
            shapeStyle: .mockRandom(),
            text: .mockRandom(),
            textPosition: .mockRandom(),
            textStyle: .mockRandom(),
            width: .mockRandom(),
            x: .mockRandom(),
            y: .mockRandom()
        )
    }

    static func mockWith(
        border: SRShapeBorder? = .mockAny(),
        height: Int64 = .mockAny(),
        id: Int64 = .mockAny(),
        shapeStyle: SRShapeStyle? = .mockAny(),
        text: String = .mockAny(),
        textPosition: SRTextPosition? = .mockAny(),
        textStyle: SRTextStyle = .mockAny(),
        type: String = .mockAny(),
        width: Int64 = .mockAny(),
        x: Int64 = .mockAny(),
        y: Int64 = .mockAny()
    ) -> SRTextWireframe {
        return SRTextWireframe(
            border: border,
            height: height,
            id: id,
            shapeStyle: shapeStyle,
            text: text,
            textPosition: textPosition,
            textStyle: textStyle,
            width: width,
            x: x,
            y: y
        )
    }
}

extension SRTextStyle: AnyMockable, RandomMockable {
    static func mockAny() -> SRTextStyle {
        return .mockWith()
    }

    static func mockRandom() -> SRTextStyle {
        return SRTextStyle(
            color: .mockRandom(),
            family: .mockRandom(),
            size: .mockRandom()
        )
    }

    static func mockWith(
        color: String = .mockAny(),
        family: String = .mockAny(),
        size: Int64 = .mockAny()
    ) -> SRTextStyle {
        return SRTextStyle(
            color: color,
            family: family,
            size: size
        )
    }
}

extension SRTextPosition: AnyMockable, RandomMockable {
    static func mockAny() -> SRTextPosition {
        return .mockWith()
    }

    static func mockRandom() -> SRTextPosition {
        return SRTextPosition(
            alignment: .mockRandom(),
            padding: .mockRandom()
        )
    }

    static func mockWith(
        alignment: Alignment? = .mockAny(),
        padding: Padding? = .mockAny()
    ) -> SRTextPosition {
        return SRTextPosition(
            alignment: alignment,
            padding: padding
        )
    }
}

extension SRTextPosition.Padding: AnyMockable, RandomMockable {
    static func mockAny() -> SRTextPosition.Padding {
        return .mockWith()
    }

    static func mockRandom() -> SRTextPosition.Padding {
        return SRTextPosition.Padding(
            bottom: .mockRandom(),
            left: .mockRandom(),
            right: .mockRandom(),
            top: .mockRandom()
        )
    }

    static func mockWith(
        bottom: Int64? = .mockAny(),
        left: Int64? = .mockAny(),
        right: Int64? = .mockAny(),
        top: Int64? = .mockAny()
    ) -> SRTextPosition.Padding {
        return SRTextPosition.Padding(
            bottom: bottom,
            left: left,
            right: right,
            top: top
        )
    }
}

extension SRTextPosition.Alignment: AnyMockable, RandomMockable {
    static func mockAny() -> SRTextPosition.Alignment {
        return .mockWith()
    }

    static func mockRandom() -> SRTextPosition.Alignment {
        return SRTextPosition.Alignment(
            horizontal: .mockRandom(),
            vertical: .mockRandom()
        )
    }

    static func mockWith(
        horizontal: Horizontal? = .mockAny(),
        vertical: Vertical? = .mockAny()
    ) -> SRTextPosition.Alignment {
        return SRTextPosition.Alignment(
            horizontal: horizontal,
            vertical: vertical
        )
    }
}

extension SRTextPosition.Alignment.Vertical: AnyMockable, RandomMockable {
    static func mockAny() -> SRTextPosition.Alignment.Vertical {
        return .top
    }

    static func mockRandom() -> SRTextPosition.Alignment.Vertical {
        return [.top, .bottom, .center].randomElement()!
    }
}

extension SRTextPosition.Alignment.Horizontal: AnyMockable, RandomMockable {
    static func mockAny() -> SRTextPosition.Alignment.Horizontal {
        return .left
    }

    static func mockRandom() -> SRTextPosition.Alignment.Horizontal {
        return [.left, .right, .center].randomElement()!
    }
}

extension SRShapeWireframe: AnyMockable, RandomMockable {
    static func mockAny() -> SRShapeWireframe {
        return .mockWith()
    }

    static func mockRandom() -> SRShapeWireframe {
        return .mockRandomWith(id: .mockRandom())
    }

    static func mockRandomWith(id: WireframeID) -> SRShapeWireframe {
        return SRShapeWireframe(
            border: .mockRandom(),
            height: .mockRandom(),
            id: id,
            shapeStyle: .mockRandom(),
            width: .mockRandom(),
            x: .mockRandom(),
            y: .mockRandom()
        )
    }

    static func mockWith(
        border: SRShapeBorder? = .mockAny(),
        height: Int64 = .mockAny(),
        id: Int64 = .mockAny(),
        shapeStyle: SRShapeStyle? = .mockAny(),
        width: Int64 = .mockAny(),
        x: Int64 = .mockAny(),
        y: Int64 = .mockAny()
    ) -> SRShapeWireframe {
        return SRShapeWireframe(
            border: border,
            height: height,
            id: id,
            shapeStyle: shapeStyle,
            width: width,
            x: x,
            y: y
        )
    }
}

extension SRShapeStyle: AnyMockable, RandomMockable {
    static func mockAny() -> SRShapeStyle {
        return .mockWith()
    }

    static func mockRandom() -> SRShapeStyle {
        return SRShapeStyle(
            backgroundColor: .mockRandom(),
            cornerRadius: .mockRandom(),
            opacity: .mockRandom()
        )
    }

    static func mockWith(
        backgroundColor: String? = .mockAny(),
        cornerRadius: Double? = .mockAny(),
        opacity: Double? = .mockAny()
    ) -> SRShapeStyle {
        return SRShapeStyle(
            backgroundColor: backgroundColor,
            cornerRadius: cornerRadius,
            opacity: opacity
        )
    }
}

extension SRShapeBorder: AnyMockable, RandomMockable {
    static func mockAny() -> SRShapeBorder {
        return .mockWith()
    }

    static func mockRandom() -> SRShapeBorder {
        return SRShapeBorder(
            color: .mockRandom(),
            width: .mockRandom()
        )
    }

    static func mockWith(
        color: String = .mockAny(),
        width: Int64 = .mockAny()
    ) -> SRShapeBorder {
        return SRShapeBorder(
            color: color,
            width: width
        )
    }
}

extension SRWireframe: AnyMockable, RandomMockable {
    static func mockAny() -> SRWireframe {
        return .shapeWireframe(value: .mockAny())
    }

    static func mockRandom() -> SRWireframe {
        return mockRandomWith(id: .mockRandom())
    }

    static func mockRandomWith(id: WireframeID) -> SRWireframe {
        return [
            .shapeWireframe(value: .mockRandomWith(id: id)),
            .textWireframe(value: .mockRandomWith(id: id))
        ].randomElement()!
    }
}
