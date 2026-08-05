/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
@preconcurrency import CoreGraphics
@preconcurrency import DatadogInternal

import Foundation
import QuartzCore
import UIKit

/// Snapshot of a `CALayer` subtree.
///
/// It stores the layer identity, geometry, style, privacy state, and semantic
/// payload needed by later Session Replay recording steps.
/// Frames are captured in the root layer coordinate space, matching the
/// coordinate space used by Session Replay wireframes.
@available(iOS 13.0, tvOS 13.0, *)
internal struct CALayerSnapshot: Sendable {
    let layer: CALayerReference
    let replayID: Int64
    var observation: SemanticObservation

    let layerClass: AnyClass
    let delegateClass: AnyClass?
    let contentsClass: AnyClass?

    let textAndInputPrivacyLevel: TextAndInputPrivacyLevel
    let imagePrivacyLevel: ImagePrivacyLevel
    let isPrivate: Bool

    let bounds: CGRect
    let position: CGPoint
    let zPosition: CGFloat
    let transform: CATransform3D

    /// The layer's frame in the root layer coordinate space.
    var absoluteFrame: CGRect

    /// The geometry used to capture this layer's rendered content.
    var contentGeometry: ContentGeometry

    var sublayers: [CALayerSnapshot]
    /// Live descendant layers omitted from `sublayers` but captured when this layer is rendered as an image.
    let dependencies: [CALayerReference]
    let sublayerTransform: CATransform3D

    let mask: Mask?
    let masksToBounds: Bool

    let isOpaque: Bool

    let backgroundColor: CGColor?
    let cornerRadii: CornerRadii
    let cornerCurve: CALayerCornerCurve
    let borderWidth: CGFloat
    let borderColor: CGColor?
    var opacity: Float
    let allowsGroupOpacity: Bool

    let compositingFilter: CompositingFilter?
    let filters: [Filter]

    let shadowColor: CGColor?
    let shadowOpacity: Float
    let shadowOffset: CGSize
    let shadowRadius: CGFloat
    let shadowPath: CGPath?
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    /// Describes the bounds and placement of a layer's rendered content.
    struct ContentGeometry: Sendable {
        /// The full content bounds in the layer's coordinate space.
        let renderBounds: CGRect

        /// The captured portion of `renderBounds`, in the layer's coordinate space.
        let localRect: CGRect

        /// The captured content frame in the root layer's coordinate space.
        var frame: CGRect

        /// Whether `localRect` contains only part of `renderBounds`.
        var isPartial: Bool {
            !renderBounds.equalTo(localRect)
        }
    }

    @MainActor
    init?(from root: CALayer, in context: Context) {
        let privacy = ResolvedPrivacy(
            textAndInputPrivacyLevel: context.textAndInputPrivacyLevel,
            imagePrivacyLevel: context.imagePrivacyLevel,
            isPrivate: false
        )

        self.init(
            from: root,
            rootLayer: root,
            visibleBounds: root.bounds,
            privacy: privacy,
            context: context
        )
    }

    @MainActor
    private init?(
        from layer: CALayer,
        rootLayer: CALayer,
        visibleBounds: CGRect,
        privacy: ResolvedPrivacy,
        context: Context
    ) {
        guard !layer.isHidden, layer.opacity > 0 else {
            return nil
        }

        let absoluteFrame = layer.convert(layer.bounds, to: rootLayer)

        guard
            !(absoluteFrame.isEmpty && layer.masksToBounds),
            absoluteFrame.intersects(visibleBounds)
        else {
            return nil
        }

        var privacy = privacy
        privacy.apply(layer.privacyOverrides)

        let observation = privacy.isPrivate
            ? SemanticObservation(semantics: .layer, ignoresSublayers: true)
            : SemanticObservation(layer: layer, absoluteFrame: absoluteFrame, context: context)

        if observation.ignoresImagePrivacy, layer.privacyOverrides?.imagePrivacy == nil {
            privacy.imagePrivacyLevel = .maskNone
        }

        let childVisibleBounds = layer.masksToBounds
            ? absoluteFrame.intersection(visibleBounds)
            : visibleBounds

        let sublayers = if observation.ignoresSublayers || childVisibleBounds.isEmpty {
            [CALayerSnapshot]()
        } else {
            layer.sublayers?.compactMap {
                CALayerSnapshot(
                    from: $0,
                    rootLayer: rootLayer,
                    visibleBounds: childVisibleBounds,
                    privacy: privacy,
                    context: context
                )
            } ?? []
        }

        let dependencies: [CALayer] = if observation.ignoresSublayers && !childVisibleBounds.isEmpty {
            layer.sublayers?.flatMap {
                $0.visibleDependencies(
                    rootLayer: rootLayer,
                    visibleBounds: childVisibleBounds
                )
            } ?? []
        } else {
            []
        }

        let contentGeometry = ContentGeometry(
            layer: layer,
            rootLayer: rootLayer,
            absoluteFrame: absoluteFrame,
            visibleBounds: visibleBounds,
            dependencies: dependencies
        )

        var cornerRadii = CornerRadii()

        if let cornerRadiiValue = layer.safeValue(forKey: "cornerRadii") as? NSValue {
            // SwiftUI layers store per-corner radii separately.
            cornerRadiiValue.getValue(&cornerRadii)
        }

        if cornerRadii == .zero {
            if layer.cornerRadius.isFinite, layer.cornerRadius > 0 {
                cornerRadii = CornerRadii(
                    cornerRadius: layer.cornerRadius,
                    maskedCorners: layer.maskedCorners
                )
            }
        }

        self.init(
            layer: .init(layer),
            replayID: layer.replayID,
            observation: observation,
            layerClass: type(of: layer),
            delegateClass: layer.delegate.map { type(of: $0) },
            contentsClass: layer.contents.map { type(of: $0 as AnyObject) },
            textAndInputPrivacyLevel: privacy.textAndInputPrivacyLevel,
            imagePrivacyLevel: privacy.imagePrivacyLevel,
            isPrivate: privacy.isPrivate,
            bounds: layer.bounds,
            position: layer.position,
            zPosition: layer.zPosition,
            transform: layer.transform,
            absoluteFrame: absoluteFrame,
            contentGeometry: contentGeometry,
            sublayers: sublayers,
            dependencies: dependencies.map(CALayerReference.init),
            sublayerTransform: layer.sublayerTransform,
            mask: layer.mask.map(Mask.init),
            masksToBounds: layer.masksToBounds,
            isOpaque: layer.isOpaque,
            backgroundColor: layer.backgroundColor?.safeCast,
            cornerRadii: cornerRadii,
            cornerCurve: layer.cornerCurve,
            borderWidth: layer.borderWidth,
            borderColor: layer.borderColor?.safeCast,
            opacity: layer.opacity,
            allowsGroupOpacity: layer.allowsGroupOpacity,
            compositingFilter: layer.compositingFilter.flatMap(CompositingFilter.init),
            filters: layer.filters?.compactMap(Filter.init) ?? [],
            shadowColor: layer.shadowColor?.safeCast,
            shadowOpacity: layer.shadowOpacity,
            shadowOffset: layer.shadowOffset,
            shadowRadius: layer.shadowRadius,
            shadowPath: layer.shadowPath
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.ContentGeometry {
    @MainActor
    fileprivate init(
        layer: CALayer,
        rootLayer: CALayer,
        absoluteFrame: CGRect,
        visibleBounds: CGRect,
        dependencies: [CALayer]
    ) {
        let renderBounds = layer.masksToBounds
            ? layer.bounds
            : dependencies.reduce(into: layer.bounds) { bounds, dependency in
                bounds = bounds.union(dependency.convert(dependency.bounds, to: layer))
            }

        let rendersLayerBounds = renderBounds.equalTo(layer.bounds)
        let renderFrame = rendersLayerBounds
            ? absoluteFrame
            : layer.convert(renderBounds, to: rootLayer)

        let isOversized = renderBounds.width > rootLayer.bounds.width
            || renderBounds.height > rootLayer.bounds.height

        let visibleRenderFrame = rendersLayerBounds
            ? renderFrame.intersection(visibleBounds)
            : renderFrame.intersection(rootLayer.bounds)

        self.init(
            renderBounds: renderBounds,
            localRect: isOversized
                ? layer.convert(visibleRenderFrame, from: rootLayer)
                : renderBounds,
            frame: isOversized ? visibleRenderFrame : renderFrame
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    fileprivate struct ResolvedPrivacy {
        var textAndInputPrivacyLevel: TextAndInputPrivacyLevel
        var imagePrivacyLevel: ImagePrivacyLevel
        var isPrivate: Bool

        mutating func apply(_ overrides: PrivacyOverrides?) {
            guard let overrides else {
                return
            }

            textAndInputPrivacyLevel = overrides.textAndInputPrivacy ?? textAndInputPrivacyLevel
            imagePrivacyLevel = overrides.imagePrivacy ?? imagePrivacyLevel
            isPrivate = isPrivate || overrides.hide == true
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayer {
    @MainActor fileprivate var privacyOverrides: SessionReplayPrivacyOverrides? {
        (delegate as? UIView)?.dd._privacyOverrides
    }

    @MainActor
    func visibleDependencies(rootLayer: CALayer, visibleBounds: CGRect) -> [CALayer] {
        guard !isHidden, opacity > 0 else {
            return []
        }

        let absoluteFrame = convert(bounds, to: rootLayer)

        guard
            !(absoluteFrame.isEmpty && masksToBounds),
            absoluteFrame.intersects(visibleBounds)
        else {
            return []
        }

        let childVisibleBounds = masksToBounds
            ? absoluteFrame.intersection(visibleBounds)
            : visibleBounds

        let sublayerDependencies = if childVisibleBounds.isEmpty {
            [CALayer]()
        } else {
            sublayers?.flatMap {
                $0.visibleDependencies(
                    rootLayer: rootLayer,
                    visibleBounds: childVisibleBounds
                )
            } ?? []
        }

        return CollectionOfOne(self) + sublayerDependencies
    }
}
#endif
