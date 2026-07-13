/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    struct Mask: Sendable, Equatable {
        let replayID: Int64
        let layer: CALayerReference
        let frame: CGRect
        let dependencies: [CALayerReference]

        @MainActor
        init(_ layer: CALayer) {
            self.replayID = layer.replayID
            self.layer = .init(layer)
            self.frame = layer.frame
            self.dependencies = layer.maskDependencies()
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayer {
    @MainActor
    fileprivate func maskDependencies() -> [CALayerReference] {
        guard !isHidden, opacity > 0 else {
            return [CALayerReference(self)]
        }

        let sublayerDependencies = sublayers?.flatMap {
            $0.maskDependencies()
        } ?? []

        return CollectionOfOne(CALayerReference(self)) + sublayerDependencies
    }
}
#endif
