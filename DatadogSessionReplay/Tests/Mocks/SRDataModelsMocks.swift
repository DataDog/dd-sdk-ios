/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

// MARK: - Wireframe Mocks

extension SRTextWireframe: AnyMockable, RandomMockable {
    public static func mockAny() -> SRTextWireframe {
        return .mockWith()
    }

    public static func mockRandom() -> SRTextWireframe {
        return .mockRandomWith(id: .mockRandom())
    }

    static func mockRandomWith(id: WireframeID) -> SRTextWireframe {
        return SRTextWireframe(
            border: .mockRandom(),
            clip: .mockRandom(),
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
        clip: SRContentClip? = .mockAny(),
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
            clip: clip,
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
    public static func mockAny() -> SRTextStyle {
        return .mockWith()
    }

    public static func mockRandom() -> SRTextStyle {
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
    public static func mockAny() -> SRTextPosition {
        return .mockWith()
    }

    public static func mockRandom() -> SRTextPosition {
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
    public static func mockAny() -> SRTextPosition.Padding {
        return .mockWith()
    }

    public static func mockRandom() -> SRTextPosition.Padding {
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
    public static func mockAny() -> SRTextPosition.Alignment {
        return .mockWith()
    }

    public static func mockRandom() -> SRTextPosition.Alignment {
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
    public static func mockAny() -> SRTextPosition.Alignment.Vertical {
        return .top
    }

    public static func mockRandom() -> SRTextPosition.Alignment.Vertical {
        return [.top, .bottom, .center].randomElement()!
    }
}

extension SRTextPosition.Alignment.Horizontal: AnyMockable, RandomMockable {
    public static func mockAny() -> SRTextPosition.Alignment.Horizontal {
        return .left
    }

    public static func mockRandom() -> SRTextPosition.Alignment.Horizontal {
        return [.left, .right, .center].randomElement()!
    }
}

extension SRShapeWireframe: AnyMockable, RandomMockable {
    public static func mockAny() -> SRShapeWireframe {
        return .mockWith()
    }

    public static func mockRandom() -> SRShapeWireframe {
        return .mockRandomWith(id: .mockRandom())
    }

    static func mockRandomWith(id: WireframeID) -> SRShapeWireframe {
        return SRShapeWireframe(
            border: .mockRandom(),
            clip: .mockRandom(),
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
        clip: SRContentClip? = .mockAny(),
        height: Int64 = .mockAny(),
        id: Int64 = .mockAny(),
        shapeStyle: SRShapeStyle? = .mockAny(),
        width: Int64 = .mockAny(),
        x: Int64 = .mockAny(),
        y: Int64 = .mockAny()
    ) -> SRShapeWireframe {
        return SRShapeWireframe(
            border: border,
            clip: clip,
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
    public static func mockAny() -> SRShapeStyle {
        return .mockWith()
    }

    public static func mockRandom() -> SRShapeStyle {
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
    public static func mockAny() -> SRShapeBorder {
        return .mockWith()
    }

    public static func mockRandom() -> SRShapeBorder {
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

extension SRContentClip: AnyMockable, RandomMockable {
    public static func mockAny() -> SRContentClip {
        return .mockWith()
    }

    public static func mockRandom() -> SRContentClip {
        return SRContentClip(
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
    ) -> SRContentClip {
        return SRContentClip(
            bottom: bottom,
            left: left,
            right: right,
            top: top
        )
    }
}

extension SRPlaceholderWireframe: AnyMockable, RandomMockable {
    public static func mockAny() -> SRPlaceholderWireframe {
        return SRPlaceholderWireframe(
            clip: .mockAny(),
            height: .mockAny(),
            id: .mockAny(),
            width: .mockAny(),
            x: .mockAny(),
            y: .mockAny()
        )
    }

    public static func mockRandom() -> SRPlaceholderWireframe {
        return SRPlaceholderWireframe(
            clip: .mockRandom(),
            height: .mockRandom(),
            id: .mockRandom(),
            width: .mockRandom(),
            x: .mockRandom(),
            y: .mockRandom()
        )
    }

    static func mockWith(
        clip: SRContentClip? = .mockAny(),
        height: Int64 = .mockAny(),
        id: Int64 = .mockAny(),
        width: Int64 = .mockAny(),
        x: Int64 = .mockAny(),
        y: Int64 = .mockAny()
    ) -> SRPlaceholderWireframe {
        return SRPlaceholderWireframe(
            clip: clip,
            height: height,
            id: id,
            width: width,
            x: x,
            y: y
        )
    }

    static func mockRandomWith(id: WireframeID) -> SRPlaceholderWireframe {
        return SRPlaceholderWireframe(
            clip: .mockRandom(),
            height: .mockRandom(),
            id: id,
            width: .mockRandom(),
            x: .mockRandom(),
            y: .mockRandom()
        )
    }
}

extension SRImageWireframe: AnyMockable, RandomMockable {
    public static func mockAny() -> SRImageWireframe {
        return SRImageWireframe(
            base64: .mockAny(),
            border: .mockAny(),
            clip: .mockAny(),
            height: .mockAny(),
            id: .mockAny(),
            isEmpty: .mockAny(),
            mimeType: .mockAny(),
            shapeStyle: .mockAny(),
            width: .mockAny(),
            x: .mockAny(),
            y: .mockAny()
        )
    }

    public static func mockRandom() -> SRImageWireframe {
        return SRImageWireframe(
            base64: .mockRandom(),
            border: .mockRandom(),
            clip: .mockRandom(),
            height: .mockRandom(),
            id: .mockRandom(),
            isEmpty: .mockRandom(),
            mimeType: .mockRandom(),
            shapeStyle: .mockRandom(),
            width: .mockRandom(),
            x: .mockRandom(),
            y: .mockRandom()
        )
    }

    static func mockWith(
        base64: String? = .mockAny(),
        border: SRShapeBorder? = .mockAny(),
        clip: SRContentClip? = .mockAny(),
        height: Int64 = .mockAny(),
        id: Int64 = .mockAny(),
        isEmpty: Bool = .mockAny(),
        mimeType: String? = .mockAny(),
        shapeStyle: SRShapeStyle? = .mockAny(),
        width: Int64 = .mockAny(),
        x: Int64 = .mockAny(),
        y: Int64 = .mockAny()
    ) -> SRImageWireframe {
        return SRImageWireframe(
            base64: base64,
            border: border,
            clip: clip,
            height: height,
            id: id,
            isEmpty: isEmpty,
            mimeType: mimeType,
            shapeStyle: shapeStyle,
            width: width,
            x: x,
            y: y
        )
    }

    static func mockRandomWith(id: WireframeID) -> SRImageWireframe {
        return SRImageWireframe(
            base64: .mockRandom(),
            border: .mockRandom(),
            clip: .mockRandom(),
            height: .mockRandom(),
            id: id,
            isEmpty: .mockRandom(),
            mimeType: .mockRandom(),
            shapeStyle: .mockRandom(),
            width: .mockRandom(),
            x: .mockRandom(),
            y: .mockRandom()
        )
    }
}

extension SRWireframe: AnyMockable, RandomMockable {
    public static func mockAny() -> SRWireframe {
        return .shapeWireframe(value: .mockAny())
    }

    public static func mockRandom() -> SRWireframe {
        return mockRandomWith(id: .mockRandom())
    }

    static func mockRandomWith(id: WireframeID) -> SRWireframe {
        return [
            .shapeWireframe(value: .mockRandomWith(id: id)),
            .textWireframe(value: .mockRandomWith(id: id))
        ].randomElement()!
    }
}

// MARK: - Record Mocks

extension SRRecord: AnyMockable, RandomMockable {
    public static func mockAny() -> SRRecord {
        return .fullSnapshotRecord(value: .mockAny())
    }

    public static func mockRandom() -> SRRecord {
        return [
            .fullSnapshotRecord(value: .mockRandom()),
            .incrementalSnapshotRecord(value: .mockRandom()),
            .metaRecord(value: .mockRandom()),
            .focusRecord(value: .mockRandom()),
            .viewEndRecord(value: .mockRandom()),
            .visualViewportRecord(value: .mockRandom())
        ].randomElement()!
    }
}

extension SRVisualViewportRecord: AnyMockable, RandomMockable {
    public static func mockAny() -> SRVisualViewportRecord {
        return .mockWith()
    }

    public static func mockRandom() -> SRVisualViewportRecord {
        return SRVisualViewportRecord(
            data: .mockRandom(),
            timestamp: .mockRandom()
        )
    }

    static func mockWith(
        data: Data = .mockAny(),
        timestamp: Int64 = .mockAny()
    ) -> SRVisualViewportRecord {
        return SRVisualViewportRecord(
            data: data,
            timestamp: timestamp
        )
    }
}

extension SRVisualViewportRecord.Data: AnyMockable, RandomMockable {
    public static func mockAny() -> SRVisualViewportRecord.Data {
        return .mockWith()
    }

    public static func mockRandom() -> SRVisualViewportRecord.Data {
        return SRVisualViewportRecord.Data(
            height: .mockRandom(),
            offsetLeft: .mockRandom(),
            offsetTop: .mockRandom(),
            pageLeft: .mockRandom(),
            pageTop: .mockRandom(),
            scale: .mockRandom(),
            width: .mockRandom()
        )
    }

    static func mockWith(
        height: Double = .mockAny(),
        offsetLeft: Double = .mockAny(),
        offsetTop: Double = .mockAny(),
        pageLeft: Double = .mockAny(),
        pageTop: Double = .mockAny(),
        scale: Double = .mockAny(),
        width: Double = .mockAny()
    ) -> SRVisualViewportRecord.Data {
        return SRVisualViewportRecord.Data(
            height: height,
            offsetLeft: offsetLeft,
            offsetTop: offsetTop,
            pageLeft: pageLeft,
            pageTop: pageTop,
            scale: scale,
            width: width
        )
    }
}

extension SRViewEndRecord: AnyMockable, RandomMockable {
    public static func mockAny() -> SRViewEndRecord {
        return .mockWith()
    }

    public static func mockRandom() -> SRViewEndRecord {
        return SRViewEndRecord(
            timestamp: .mockRandom()
        )
    }

    static func mockWith(
        timestamp: Int64 = .mockAny()
    ) -> SRViewEndRecord {
        return SRViewEndRecord(
            timestamp: timestamp
        )
    }
}

extension SRFocusRecord: AnyMockable, RandomMockable {
    public static func mockAny() -> SRFocusRecord {
        return .mockWith()
    }

    public static func mockRandom() -> SRFocusRecord {
        return SRFocusRecord(
            data: .mockRandom(),
            timestamp: .mockRandom()
        )
    }

    static func mockWith(
        data: Data = .mockAny(),
        timestamp: Int64 = .mockAny()
    ) -> SRFocusRecord {
        return SRFocusRecord(
            data: data,
            timestamp: timestamp
        )
    }
}

extension SRFocusRecord.Data: AnyMockable, RandomMockable {
    public static func mockAny() -> SRFocusRecord.Data {
        return .mockWith()
    }

    public static func mockRandom() -> SRFocusRecord.Data {
        return SRFocusRecord.Data(
            hasFocus: .mockRandom()
        )
    }

    static func mockWith(
        hasFocus: Bool = .mockAny()
    ) -> SRFocusRecord.Data {
        return SRFocusRecord.Data(
            hasFocus: hasFocus
        )
    }
}

extension SRMetaRecord: AnyMockable, RandomMockable {
    public static func mockAny() -> SRMetaRecord {
        return .mockWith()
    }

    public static func mockRandom() -> SRMetaRecord {
        return SRMetaRecord(
            data: .mockRandom(),
            timestamp: .mockRandom()
        )
    }

    static func mockWith(
        data: Data = .mockAny(),
        timestamp: Int64 = .mockAny()
    ) -> SRMetaRecord {
        return SRMetaRecord(
            data: data,
            timestamp: timestamp
        )
    }
}

extension SRMetaRecord.Data: AnyMockable, RandomMockable {
    public static func mockAny() -> SRMetaRecord.Data {
        return .mockWith()
    }

    public static func mockRandom() -> SRMetaRecord.Data {
        return SRMetaRecord.Data(
            height: .mockRandom(),
            href: .mockRandom(),
            width: .mockRandom()
        )
    }

    static func mockWith(
        height: Int64 = .mockAny(),
        href: String? = .mockAny(),
        width: Int64 = .mockAny()
    ) -> SRMetaRecord.Data {
        return SRMetaRecord.Data(
            height: height,
            href: href,
            width: width
        )
    }
}

extension SRIncrementalSnapshotRecord: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord {
        return .mockWith()
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord {
        return SRIncrementalSnapshotRecord(
            data: .mockRandom(),
            timestamp: .mockRandom()
        )
    }

    static func mockWith(
        data: Data = .mockAny(),
        timestamp: Int64 = .mockAny()
    ) -> SRIncrementalSnapshotRecord {
        return SRIncrementalSnapshotRecord(
            data: data,
            timestamp: timestamp
        )
    }
}

extension SRIncrementalSnapshotRecord.Data: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data {
        return .mutationData(value: .mockAny())
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data {
        return [
            .mutationData(value: .mockRandom()),
            .touchData(value: .mockRandom()),
            .viewportResizeData(value: .mockRandom()),
            .pointerInteractionData(value: .mockRandom())
        ].randomElement()!
    }
}

extension SRIncrementalSnapshotRecord.Data.PointerInteractionData: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.PointerInteractionData {
        return .mockWith()
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.PointerInteractionData {
        return SRIncrementalSnapshotRecord.Data.PointerInteractionData(
            pointerEventType: .mockRandom(),
            pointerId: .mockRandom(),
            pointerType: .mockRandom(),
            x: .mockRandom(),
            y: .mockRandom()
        )
    }

    static func mockWith(
        pointerEventType: PointerEventType = .mockAny(),
        pointerId: Int64 = .mockAny(),
        pointerType: PointerType = .mockAny(),
        x: Double = .mockAny(),
        y: Double = .mockAny()
    ) -> SRIncrementalSnapshotRecord.Data.PointerInteractionData {
        return SRIncrementalSnapshotRecord.Data.PointerInteractionData(
            pointerEventType: pointerEventType,
            pointerId: pointerId,
            pointerType: pointerType,
            x: x,
            y: y
        )
    }
}

extension SRIncrementalSnapshotRecord.Data.PointerInteractionData.PointerType: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.PointerInteractionData.PointerType {
        return .mouse
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.PointerInteractionData.PointerType {
        return [
            .mouse,
            .touch,
            .pen
        ].randomElement()!
    }
}

extension SRIncrementalSnapshotRecord.Data.PointerInteractionData.PointerEventType: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.PointerInteractionData.PointerEventType {
        return .down
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.PointerInteractionData.PointerEventType {
        return [
            .down,
            .up,
            .move
        ].randomElement()!
    }
}

extension SRIncrementalSnapshotRecord.Data.ViewportResizeData: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.ViewportResizeData {
        return .mockWith()
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.ViewportResizeData {
        return SRIncrementalSnapshotRecord.Data.ViewportResizeData(
            height: .mockRandom(),
            width: .mockRandom()
        )
    }

    static func mockWith(
        height: Int64 = .mockAny(),
        width: Int64 = .mockAny()
    ) -> SRIncrementalSnapshotRecord.Data.ViewportResizeData {
        return SRIncrementalSnapshotRecord.Data.ViewportResizeData(
            height: height,
            width: width
        )
    }
}

extension SRIncrementalSnapshotRecord.Data.TouchData: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.TouchData {
        return .mockWith()
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.TouchData {
        return SRIncrementalSnapshotRecord.Data.TouchData(
            positions: .mockRandom()
        )
    }

    static func mockWith(
        positions: [Positions]? = .mockAny()
    ) -> SRIncrementalSnapshotRecord.Data.TouchData {
        return SRIncrementalSnapshotRecord.Data.TouchData(
            positions: positions
        )
    }
}

extension SRIncrementalSnapshotRecord.Data.TouchData.Positions: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.TouchData.Positions {
        return .mockWith()
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.TouchData.Positions {
        return SRIncrementalSnapshotRecord.Data.TouchData.Positions(
            id: .mockRandom(),
            timestamp: .mockRandom(),
            x: .mockRandom(),
            y: .mockRandom()
        )
    }

    static func mockWith(
        id: Int64 = .mockAny(),
        timestamp: Int64 = .mockAny(),
        x: Int64 = .mockAny(),
        y: Int64 = .mockAny()
    ) -> SRIncrementalSnapshotRecord.Data.TouchData.Positions {
        return SRIncrementalSnapshotRecord.Data.TouchData.Positions(
            id: id,
            timestamp: timestamp,
            x: x,
            y: y
        )
    }
}

extension SRIncrementalSnapshotRecord.Data.MutationData: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.MutationData {
        return .mockWith()
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.MutationData {
        return SRIncrementalSnapshotRecord.Data.MutationData(
            adds: .mockRandom(),
            removes: .mockRandom(),
            updates: .mockRandom()
        )
    }

    static func mockWith(
        adds: [Adds] = .mockAny(),
        removes: [Removes] = .mockAny(),
        updates: [Updates] = .mockAny()
    ) -> SRIncrementalSnapshotRecord.Data.MutationData {
        return SRIncrementalSnapshotRecord.Data.MutationData(
            adds: adds,
            removes: removes,
            updates: updates
        )
    }
}

extension SRIncrementalSnapshotRecord.Data.MutationData.Updates: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.MutationData.Updates {
        return .textWireframeUpdate(value: .mockAny())
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.MutationData.Updates {
        return [
            .textWireframeUpdate(value: .mockRandom()),
            .shapeWireframeUpdate(value: .mockRandom())
        ].randomElement()!
    }
}

extension SRIncrementalSnapshotRecord.Data.MutationData.Updates.ShapeWireframeUpdate: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.MutationData.Updates.ShapeWireframeUpdate {
        return .mockWith()
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.MutationData.Updates.ShapeWireframeUpdate {
        return SRIncrementalSnapshotRecord.Data.MutationData.Updates.ShapeWireframeUpdate(
            border: .mockRandom(),
            clip: .mockRandom(),
            height: .mockRandom(),
            id: .mockRandom(),
            shapeStyle: .mockRandom(),
            width: .mockRandom(),
            x: .mockRandom(),
            y: .mockRandom()
        )
    }

    static func mockWith(
        border: SRShapeBorder? = .mockAny(),
        clip: SRContentClip? = .mockAny(),
        height: Int64? = .mockAny(),
        id: Int64 = .mockAny(),
        shapeStyle: SRShapeStyle? = .mockAny(),
        width: Int64? = .mockAny(),
        x: Int64? = .mockAny(),
        y: Int64? = .mockAny()
    ) -> SRIncrementalSnapshotRecord.Data.MutationData.Updates.ShapeWireframeUpdate {
        return SRIncrementalSnapshotRecord.Data.MutationData.Updates.ShapeWireframeUpdate(
            border: border,
            clip: clip,
            height: height,
            id: id,
            shapeStyle: shapeStyle,
            width: width,
            x: x,
            y: y
        )
    }
}

extension SRIncrementalSnapshotRecord.Data.MutationData.Updates.TextWireframeUpdate: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.MutationData.Updates.TextWireframeUpdate {
        return .mockWith()
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.MutationData.Updates.TextWireframeUpdate {
        return SRIncrementalSnapshotRecord.Data.MutationData.Updates.TextWireframeUpdate(
            border: .mockRandom(),
            clip: .mockRandom(),
            height: .mockRandom(),
            id: .mockRandom(),
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
        clip: SRContentClip? = .mockAny(),
        height: Int64? = .mockAny(),
        id: Int64 = .mockAny(),
        shapeStyle: SRShapeStyle? = .mockAny(),
        text: String? = .mockAny(),
        textPosition: SRTextPosition? = .mockAny(),
        textStyle: SRTextStyle? = .mockAny(),
        width: Int64? = .mockAny(),
        x: Int64? = .mockAny(),
        y: Int64? = .mockAny()
    ) -> SRIncrementalSnapshotRecord.Data.MutationData.Updates.TextWireframeUpdate {
        return SRIncrementalSnapshotRecord.Data.MutationData.Updates.TextWireframeUpdate(
            border: border,
            clip: clip,
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

extension SRIncrementalSnapshotRecord.Data.MutationData.Removes: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.MutationData.Removes {
        return .mockWith()
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.MutationData.Removes {
        return SRIncrementalSnapshotRecord.Data.MutationData.Removes(
            id: .mockRandom()
        )
    }

    static func mockWith(
        id: Int64 = .mockAny()
    ) -> SRIncrementalSnapshotRecord.Data.MutationData.Removes {
        return SRIncrementalSnapshotRecord.Data.MutationData.Removes(
            id: id
        )
    }
}

extension SRIncrementalSnapshotRecord.Data.MutationData.Adds: AnyMockable, RandomMockable {
    public static func mockAny() -> SRIncrementalSnapshotRecord.Data.MutationData.Adds {
        return .mockWith()
    }

    public static func mockRandom() -> SRIncrementalSnapshotRecord.Data.MutationData.Adds {
        return SRIncrementalSnapshotRecord.Data.MutationData.Adds(
            previousId: .mockRandom(),
            wireframe: .mockRandom()
        )
    }

    static func mockWith(
        previousId: Int64? = .mockAny(),
        wireframe: SRWireframe = .mockAny()
    ) -> SRIncrementalSnapshotRecord.Data.MutationData.Adds {
        return SRIncrementalSnapshotRecord.Data.MutationData.Adds(
            previousId: previousId,
            wireframe: wireframe
        )
    }
}

extension SRFullSnapshotRecord: AnyMockable, RandomMockable {
    public static func mockAny() -> SRFullSnapshotRecord {
        return .mockWith()
    }

    public static func mockRandom() -> SRFullSnapshotRecord {
        return SRFullSnapshotRecord(
            data: .mockRandom(),
            timestamp: .mockRandom()
        )
    }

    static func mockWith(
        data: Data = .mockAny(),
        timestamp: Int64 = .mockAny()
    ) -> SRFullSnapshotRecord {
        return SRFullSnapshotRecord(
            data: data,
            timestamp: timestamp
        )
    }
}

extension SRFullSnapshotRecord.Data: AnyMockable, RandomMockable {
    public static func mockAny() -> SRFullSnapshotRecord.Data {
        return .mockWith()
    }

    public static func mockRandom() -> SRFullSnapshotRecord.Data {
        return SRFullSnapshotRecord.Data(
            wireframes: .mockRandom()
        )
    }

    static func mockWith(
        wireframes: [SRWireframe] = .mockAny()
    ) -> SRFullSnapshotRecord.Data {
        return SRFullSnapshotRecord.Data(
            wireframes: wireframes
        )
    }
}

// MARK: - Segment mocks

extension SRSegment: AnyMockable, RandomMockable {
    public static func mockAny() -> SRSegment {
        return .mockWith()
    }

    public static func mockRandom() -> SRSegment {
        return SRSegment(
            application: .mockRandom(),
            end: .mockRandom(),
            hasFullSnapshot: .mockRandom(),
            indexInView: .mockRandom(),
            records: .mockRandom(),
            recordsCount: .mockRandom(),
            session: .mockRandom(),
            source: .mockRandom(),
            start: .mockRandom(),
            view: .mockRandom()
        )
    }

    static func mockWith(
        application: Application = .mockAny(),
        end: Int64 = .mockAny(),
        hasFullSnapshot: Bool? = .mockAny(),
        indexInView: Int64? = .mockAny(),
        records: [SRRecord] = .mockAny(),
        recordsCount: Int64 = .mockAny(),
        session: Session = .mockAny(),
        source: Source = .mockAny(),
        start: Int64 = .mockAny(),
        view: View = .mockAny()
    ) -> SRSegment {
        return SRSegment(
            application: application,
            end: end,
            hasFullSnapshot: hasFullSnapshot,
            indexInView: indexInView,
            records: records,
            recordsCount: recordsCount,
            session: session,
            source: source,
            start: start,
            view: view
        )
    }
}

extension SRSegment.View: AnyMockable, RandomMockable {
    public static func mockAny() -> SRSegment.View {
        return .mockWith()
    }

    public static func mockRandom() -> SRSegment.View {
        return SRSegment.View(
            id: .mockRandom()
        )
    }

    static func mockWith(
        id: String = .mockAny()
    ) -> SRSegment.View {
        return SRSegment.View(
            id: id
        )
    }
}

extension SRSegment.Source: AnyMockable, RandomMockable {
    public static func mockAny() -> SRSegment.Source {
        return .android
    }

    public static func mockRandom() -> SRSegment.Source {
        return [
            .android,
            .ios,
            .flutter,
            .reactNative
        ].randomElement()!
    }
}

extension SRSegment.Session: AnyMockable, RandomMockable {
    public static func mockAny() -> SRSegment.Session {
        return .mockWith()
    }

    public static func mockRandom() -> SRSegment.Session {
        return SRSegment.Session(
            id: .mockRandom()
        )
    }

    static func mockWith(
        id: String = .mockAny()
    ) -> SRSegment.Session {
        return SRSegment.Session(
            id: id
        )
    }
}

extension SRSegment.Application: AnyMockable, RandomMockable {
    public static func mockAny() -> SRSegment.Application {
        return .mockWith()
    }

    public static func mockRandom() -> SRSegment.Application {
        return SRSegment.Application(
            id: .mockRandom()
        )
    }

    static func mockWith(
        id: String = .mockAny()
    ) -> SRSegment.Application {
        return SRSegment.Application(
            id: id
        )
    }
}

// MARK: - Convenience

internal extension SRRecord {
    var isFullSnapshotRecord: Bool {
        switch self {
        case .fullSnapshotRecord: return true
        default: return false
        }
    }

    var isIncrementalSnapshotRecord: Bool {
        switch self {
        case .incrementalSnapshotRecord: return true
        default: return false
        }
    }

    var isMetaRecord: Bool {
        switch self {
        case .metaRecord: return true
        default: return false
        }
    }

    var isFocusRecord: Bool {
        switch self {
        case .focusRecord: return true
        default: return false
        }
    }

    var isViewEndRecord: Bool {
        switch self {
        case .viewEndRecord: return true
        default: return false
        }
    }

    var isVisualViewportRecord: Bool {
        switch self {
        case .visualViewportRecord: return true
        default: return false
        }
    }

    var timestamp: Int64 {
        switch self {
        case .fullSnapshotRecord(let record):           return record.timestamp
        case .incrementalSnapshotRecord(let record):    return record.timestamp
        case .metaRecord(let record):                   return record.timestamp
        case .focusRecord(let record):                  return record.timestamp
        case .viewEndRecord(let record):                return record.timestamp
        case .visualViewportRecord(let record):         return record.timestamp
        }
    }

    var incrementalSnapshot: SRIncrementalSnapshotRecord? {
        switch self {
        case .incrementalSnapshotRecord(let value): return value
        default: return nil
        }
    }

    var fullSnapshot: SRFullSnapshotRecord? {
        switch self {
        case .fullSnapshotRecord(let value): return value
        default: return nil
        }
    }
}

extension SRIncrementalSnapshotRecord {
    var pointerInteractionData: SRIncrementalSnapshotRecord.Data.PointerInteractionData? {
        switch data {
        case .pointerInteractionData(let value): return value
        default: return nil
        }
    }

    var viewportResizeData: SRIncrementalSnapshotRecord.Data.ViewportResizeData? {
        switch data {
        case .viewportResizeData(let value): return value
        default: return nil
        }
    }
}
