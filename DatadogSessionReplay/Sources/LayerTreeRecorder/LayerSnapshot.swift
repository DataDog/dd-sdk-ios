/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Immutable representation of a captured `CALayer` hierarchy.
//
// The snapshot is built on the main actor and stores the geometry, styling and identity
// metadata required by downstream optimization and rendering passes. It also computes
// deterministic path components, propagates clip intersections and resolves cumulative
// opacity through the subtree.

#if os(iOS)
@preconcurrency import CoreGraphics
import Foundation
import QuartzCore

@available(iOS 13.0, tvOS 13.0, *)
internal struct LayerSnapshot: Sendable, Equatable {
    let layer: CALayerReference
    let replayID: Int64

    var path: String {
        pathComponents.joined(separator: "/")
    }

    let pathComponents: [String]

    let frame: CGRect
    let clipRect: CGRect
    let zPosition: CGFloat
    let isAxisAligned: Bool

    let opacity: Float
    let resolvedOpacity: Float
    let isHidden: Bool
    let backgroundColor: CGColor?
    let hasContents: Bool

    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let borderColor: CGColor?
    let masksToBounds: Bool
    let hasMask: Bool

    var children: [LayerSnapshot]

    func isSnapshot(of layer: CALayer) -> Bool {
        self.layer.matches(layer)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshot {
    @MainActor
    init(from root: CALayer) {
        self.init(
            from: root,
            in: root,
            pathComponents: [root.pathComponent(0)],
            clipRect: root.bounds,
            parentOpacity: 1.0
        )
    }

    @MainActor
    private init(
        from layer: CALayer,
        in rootLayer: CALayer,
        pathComponents: [String],
        clipRect: CGRect,
        parentOpacity: Float
    ) {
        let frame = layer.convert(layer.bounds, to: rootLayer)
        let opacity = layer.opacity
        let resolvedOpacity = parentOpacity * opacity

        let nextClipRect: CGRect
        if layer.masksToBounds {
            let layerClipRect = layer.convert(layer.bounds, to: rootLayer)
            let intersection = clipRect.intersection(layerClipRect)
            nextClipRect = intersection.isNull ? .zero : intersection
        } else {
            nextClipRect = clipRect
        }

        let sublayers = layer.sublayers ?? []

        var children: [LayerSnapshot] = []
        children.reserveCapacity(sublayers.count)

        var componentTypeOccurrences: [String: Int] = [:]

        for sublayer in sublayers {
            let componentType = sublayer.componentType

            let index = componentTypeOccurrences[componentType] ?? 0
            componentTypeOccurrences[componentType] = index + 1

            let pathComponent = sublayer.pathComponent(index)
            let snapshot = LayerSnapshot(
                from: sublayer,
                in: rootLayer,
                pathComponents: pathComponents + [pathComponent],
                clipRect: nextClipRect,
                parentOpacity: resolvedOpacity
            )

            children.append(snapshot)
        }

        self.init(
            layer: .init(layer),
            replayID: layer.replayID,
            pathComponents: pathComponents,
            frame: frame,
            clipRect: clipRect,
            zPosition: layer.zPosition,
            isAxisAligned: layer.transform.isAxisAligned,
            opacity: opacity,
            resolvedOpacity: resolvedOpacity,
            isHidden: layer.isHidden,
            backgroundColor: layer.backgroundColor?.safeCast,
            hasContents: layer.contents != nil,
            cornerRadius: layer.cornerRadius,
            borderWidth: layer.borderWidth,
            borderColor: layer.borderColor?.safeCast,
            masksToBounds: layer.masksToBounds,
            hasMask: layer.mask != nil,
            children: children
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayer {
    fileprivate var componentType: String {
        [
            NSStringFromClass(type(of: self)),
            delegate.map {
                NSStringFromClass(type(of: $0))
            }
        ].compactMap(\.self).joined(separator: "-")
    }

    fileprivate func pathComponent(_ index: Int) -> String {
        "\(componentType)#\(index)"
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CATransform3D {
    fileprivate var isAxisAligned: Bool {
        guard CATransform3DIsAffine(self) else {
            return false
        }

        let affine = CATransform3DGetAffineTransform(self)
        // No rotation or rotation multiple of 90 degrees.
        return (affine.b.isNearZero && affine.c.isNearZero)
            || (affine.a.isNearZero && affine.d.isNearZero)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CGFloat {
    fileprivate var isNearZero: Bool {
        abs(self) < CGFloat(0.0001)
    }
}
#endif
