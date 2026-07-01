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
    /// Returns the image snapshot requests needed to represent this layer tree.
    func imageSnapshotRequests(for changeset: CALayerChangeset, cache: ImageSnapshotCache) -> [ImageSnapshotRequest] {
        var requests: [ImageSnapshotRequest] = []

        collectImageSnapshotRequests(
            clipRect: absoluteFrame,
            changeset: changeset,
            cache: cache,
            in: &requests
        )

        return requests
    }

    private func collectImageSnapshotRequests(
        clipRect: CGRect,
        changeset: CALayerChangeset,
        cache: ImageSnapshotCache,
        in requests: inout [ImageSnapshotRequest]
    ) {
        let visibleFrame = absoluteFrame.intersection(clipRect)

        guard !visibleFrame.isNull, !visibleFrame.isEmpty else {
            return
        }

        let previousSnapshotData = cache.snapshotData(forReplayID: replayID)
        let hasChanges = changeset.hasContentChanges(for: layer)
            || changeset.hasChanges(for: dependencies)
            || (previousSnapshotData.map { $0.dependencies != dependencies } ?? false)

        let request = ImageSnapshotRequest(
            layerSnapshot: self,
            visibleFrame: visibleFrame,
            hasChanges: hasChanges,
            previousSnapshotData: previousSnapshotData
        )

        if let request, observation.ignoresSublayers || sublayers.isEmpty {
            requests.append(request)
        } else {
            for sublayer in sublayers {
                sublayer.collectImageSnapshotRequests(
                    clipRect: masksToBounds ? visibleFrame : clipRect,
                    changeset: changeset,
                    cache: cache,
                    in: &requests
                )
            }
        }
    }

    fileprivate var allowsImageSnapshot: Bool {
        guard !isPrivate else {
            return false
        }

        switch observation.semantics {
        case .image(let image) where !image.hasContent && dependencies.isEmpty:
            return false
        case .image where imagePrivacyLevel == .maskNone:
            return true
        case .image(let image) where imagePrivacyLevel == .maskNonBundledOnly && image.isContextual:
            return true
        case .layer, .activityIndicator, .stepper:
            return true
        default:
            return false
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ImageSnapshotRequest {
    fileprivate init?(
        layerSnapshot: CALayerSnapshot,
        visibleFrame: CGRect,
        hasChanges: Bool,
        previousSnapshotData: ImageSnapshotData?
    ) {
        guard layerSnapshot.allowsImageSnapshot else {
            return nil
        }

        if layerSnapshot.layerClass == CALayer.self,
           layerSnapshot.contentsClass == nil,
           layerSnapshot.dependencies.isEmpty,
           !hasChanges,
           previousSnapshotData == nil {
            return nil
        }

        self.init(
            replayID: layerSnapshot.replayID,
            layer: layerSnapshot.layer,
            layerClass: layerSnapshot.layerClass,
            delegateClass: layerSnapshot.delegateClass,
            hasLayerSemantics: layerSnapshot.observation.semantics == .layer,
            bounds: layerSnapshot.bounds,
            absoluteFrame: layerSnapshot.absoluteFrame,
            visibleFrame: visibleFrame,
            isOpaque: layerSnapshot.isOpaque,
            hasContents: layerSnapshot.contentsClass != nil,
            dependencies: layerSnapshot.dependencies,
            hasChanges: hasChanges,
            textAndInputPrivacyLevel: layerSnapshot.textAndInputPrivacyLevel,
            imagePrivacyLevel: layerSnapshot.imagePrivacyLevel,
            previousSnapshotData: previousSnapshotData
        )
    }
}
#endif
