/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore

@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
enum LayerTreeRecorderFixtures {
    static let viewportRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    static let rootBounds = CGRect(x: 0, y: 0, width: 200, height: 300)

    static var rootLayer: CALayer {
        let root = CALayer()
        root.bounds = rootBounds
        return root
    }

    static var anyImage: CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    static func snapshot(
        layer: CALayer = .init(),
        replayID: Int64 = 0,
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
        clipRect: CGRect = .infinite,
        zPosition: CGFloat = 0,
        isAxisAligned: Bool = true,
        opacity: Float = 1.0,
        resolvedOpacity: Float? = nil,
        isHidden: Bool = false,
        backgroundColor: CGColor? = nil,
        hasContents: Bool = false,
        semantics: LayerSnapshot.Semantics = .generic,
        cornerRadius: CGFloat = 0,
        borderWidth: CGFloat = 0,
        borderColor: CGColor? = nil,
        hasMask: Bool = false,
        children: [LayerSnapshot] = []
    ) -> LayerSnapshot {
        return LayerSnapshot(
            layer: CALayerReference(layer),
            replayID: replayID,
            semantics: semantics,
            pathComponents: ["Test#\(replayID)"],
            frame: frame,
            clipRect: clipRect,
            zPosition: zPosition,
            isAxisAligned: isAxisAligned,
            opacity: opacity,
            resolvedOpacity: resolvedOpacity ?? opacity,
            isHidden: isHidden,
            backgroundColor: backgroundColor,
            hasContents: hasContents,
            cornerRadius: cornerRadius,
            borderWidth: borderWidth,
            borderColor: borderColor,
            masksToBounds: false,
            hasMask: hasMask,
            children: children
        )
    }

    static func opaqueSnapshot(
        replayID: Int64 = 0,
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    ) -> LayerSnapshot {
        snapshot(
            replayID: replayID,
            frame: frame,
            opacity: 1.0,
            backgroundColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1.0),
            hasContents: true
        )
    }

    static func changeset(
        for layer: CALayer,
        aspects: CALayerChange.Aspect.Set
    ) -> CALayerChangeset {
        CALayerChangeset([
            ObjectIdentifier(layer): .init(
                layer: .init(layer),
                aspects: aspects
            )
        ])
    }

    static func layerSnapshot(
        for layer: CALayer,
        replayID: Int64,
        in rootLayer: CALayer,
        hasContents: Bool = false,
        clipRect: CGRect? = nil,
        semantics: LayerSnapshot.Semantics = .generic
    ) -> LayerSnapshot {
        snapshot(
            layer: layer,
            replayID: replayID,
            frame: layer.convert(layer.bounds, to: rootLayer),
            clipRect: clipRect ?? rootLayer.bounds,
            hasContents: hasContents,
            semantics: semantics
        )
    }
}
#endif
