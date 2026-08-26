/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import Foundation

/// Maps layer snapshots to composition layers and mask resources.
@available(iOS 13.0, tvOS 13.0, *)
internal struct CompositionLayerBuilder {
    struct Output {
        let layer: SRCompositionLayer
        let resource: Resource?
    }

    private let maskSnapshots: [Int64: MaskSnapshotResult]

    init(maskSnapshots: [Int64: MaskSnapshotResult]) {
        self.maskSnapshots = maskSnapshots
    }

    func build(
        from snapshot: CALayerSnapshot,
        children: [SRCompositionLayerChild]
    ) -> Output {
        let resource = maskResource(for: snapshot)
        let layer = SRCompositionLayer(
            children: children,
            compositeOperation: SRCompositionLayer.CompositeOperation(
                compositingFilter: snapshot.compositingFilter,
                semantics: snapshot.observation.semantics
            ),
            height: Int64.ddWithNoOverflow(dimension: snapshot.absoluteFrame.height),
            id: snapshot.replayID,
            modifiers: snapshot.modifiers(maskImageResourceID: resource?.calculateIdentifier()),
            width: Int64.ddWithNoOverflow(dimension: snapshot.absoluteFrame.width),
            x: Int64.ddWithNoOverflow(snapshot.absoluteFrame.minX),
            y: Int64.ddWithNoOverflow(snapshot.absoluteFrame.minY)
        )

        return Output(layer: layer, resource: resource)
    }

    private func maskResource(for snapshot: CALayerSnapshot) -> Resource? {
        guard
            let mask = snapshot.mask,
            case .success(let maskSnapshot) = maskSnapshots[mask.replayID]
        else {
            return nil
        }

        return ImageSnapshotResource(image: maskSnapshot.image)
    }
}
#endif
