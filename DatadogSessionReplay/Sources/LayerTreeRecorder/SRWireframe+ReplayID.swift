/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

extension SRWireframe {
    internal enum IdentifierNamespace: Int64 {
        case shape = 1
        case text = 2
        case image = 3
        case placeholder = 4
        case embeddedContent = 5
    }
}

extension Int64 {
    internal init(namespace: SRWireframe.IdentifierNamespace, replayID: Int64) {
        self = (namespace.rawValue << 32) | replayID
    }
}

extension SRShapeWireframe {
    init(
        replayID: Int64,
        x: Int64,
        y: Int64,
        width: Int64,
        height: Int64,
        border: SRShapeBorder? = nil,
        clip: SRContentClip? = nil,
        shapeStyle: SRShapeStyle? = nil,
        permanentId: String? = nil
    ) {
        self.init(
            border: border,
            clip: clip,
            height: height,
            id: .init(namespace: .shape, replayID: replayID),
            permanentId: permanentId,
            shapeStyle: shapeStyle,
            width: width,
            x: x,
            y: y
        )
    }
}

extension SRTextWireframe {
    init(
        replayID: Int64,
        x: Int64,
        y: Int64,
        height: Int64,
        width: Int64,
        text: String,
        textStyle: SRTextStyle,
        border: SRShapeBorder? = nil,
        clip: SRContentClip? = nil,
        shapeStyle: SRShapeStyle? = nil,
        textPosition: SRTextPosition? = nil,
        permanentId: String? = nil
    ) {
        self.init(
            border: border,
            clip: clip,
            height: height,
            id: .init(namespace: .text, replayID: replayID),
            permanentId: permanentId,
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

extension SRImageWireframe {
    init(
        replayID: Int64,
        x: Int64,
        y: Int64,
        width: Int64,
        height: Int64,
        base64: String? = nil,
        border: SRShapeBorder? = nil,
        clip: SRContentClip? = nil,
        isEmpty: Bool? = nil,
        mimeType: String? = nil,
        resourceId: String? = nil,
        shapeStyle: SRShapeStyle? = nil,
        permanentId: String? = nil
    ) {
        self.init(
            base64: base64,
            border: border,
            clip: clip,
            height: height,
            id: .init(namespace: .image, replayID: replayID),
            isEmpty: isEmpty,
            mimeType: mimeType,
            permanentId: permanentId,
            resourceId: resourceId,
            shapeStyle: shapeStyle,
            width: width,
            x: x,
            y: y
        )
    }
}

extension SRPlaceholderWireframe {
    init(
        replayID: Int64,
        x: Int64,
        y: Int64,
        width: Int64,
        height: Int64,
        clip: SRContentClip? = nil,
        label: String? = nil,
        permanentId: String? = nil
    ) {
        self.init(
            clip: clip,
            height: height,
            id: .init(namespace: .placeholder, replayID: replayID),
            label: label,
            permanentId: permanentId,
            width: width,
            x: x,
            y: y
        )
    }
}

extension SREmbeddedContentWireframe {
    init(
        replayID: Int64,
        slotId: String,
        x: Int64,
        y: Int64,
        width: Int64,
        height: Int64,
        border: SRShapeBorder? = nil,
        clip: SRContentClip? = nil,
        isVisible: Bool? = nil,
        shapeStyle: SRShapeStyle? = nil,
        permanentId: String? = nil,
    ) {
        self.init(
            border: border,
            clip: clip,
            height: height,
            id: .init(namespace: .embeddedContent, replayID: replayID),
            isVisible: isVisible,
            permanentId: permanentId,
            shapeStyle: shapeStyle,
            slotId: slotId,
            width: width,
            x: x,
            y: y
        )
    }
}
#endif
