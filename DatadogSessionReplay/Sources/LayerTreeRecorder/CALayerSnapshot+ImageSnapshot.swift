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

        guard !visibleFrame.isEmpty || !masksToBounds else {
            return
        }

        if !visibleFrame.isEmpty {
            if let request = MaskSnapshotRequest(layerSnapshot: self, cache: cache, changeset: changeset) {
                requests.append(.mask(request))
            }

            let request = ContentSnapshotRequest(
                layerSnapshot: self,
                cache: cache,
                changeset: changeset
            )

            if let request, observation.ignoresSublayers || sublayers.isEmpty {
                requests.append(.content(request))
                return
            }
        }

        for sublayer in sublayers {
            sublayer.collectImageSnapshotRequests(
                clipRect: masksToBounds ? visibleFrame : clipRect,
                changeset: changeset,
                cache: cache,
                in: &requests
            )
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
        case .layer:
            return true
        default:
            return false
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension MaskSnapshotRequest {
    fileprivate init?(
        layerSnapshot: CALayerSnapshot,
        cache: ImageSnapshotCache,
        changeset: CALayerChangeset
    ) {
        // Container masks clip the generated composition layer. Leaf masks are captured
        // by the leaf content snapshot, so they do not need a separate mask request.
        guard !layerSnapshot.sublayers.isEmpty, let mask = layerSnapshot.mask, !mask.dependencies.isEmpty else {
            return nil
        }

        let previousSnapshotData = cache.maskSnapshotData(forReplayID: mask.replayID)
        let hasChanges = changeset.hasChanges(for: mask.dependencies)
            || (previousSnapshotData.map { $0.dependencies != mask.dependencies } ?? false)

        self.init(
            replayID: mask.replayID,
            layer: mask.layer,
            bounds: layerSnapshot.bounds,
            frame: mask.frame,
            dependencies: mask.dependencies,
            hasChanges: hasChanges,
            previousSnapshotData: previousSnapshotData
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ContentSnapshotRequest {
    fileprivate init?(
        layerSnapshot: CALayerSnapshot,
        cache: ImageSnapshotCache,
        changeset: CALayerChangeset
    ) {
        guard layerSnapshot.allowsImageSnapshot else {
            return nil
        }

        let previousSnapshotData = cache.contentSnapshotData(forReplayID: layerSnapshot.replayID)
        let hasChanges = changeset.hasContentChanges(for: layerSnapshot.layer)
            || changeset.hasChanges(for: layerSnapshot.dependencies)
            || (previousSnapshotData.map { $0.dependencies != layerSnapshot.dependencies } ?? false)

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
            geometry: layerSnapshot.contentGeometry,
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
