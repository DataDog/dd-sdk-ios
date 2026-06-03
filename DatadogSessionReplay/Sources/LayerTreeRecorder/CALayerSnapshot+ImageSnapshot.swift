/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore
import UIKit

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

        let request = ImageSnapshotRequest(
            layerSnapshot: self,
            visibleFrame: visibleFrame,
            hasContentChanges: changeset.hasContentChanges(for: layer),
            previousSnapshotData: cache.snapshotData(forReplayID: replayID)
        )

        if let request, observation.ignoreSublayers || sublayers.isEmpty {
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

        return observation.allowsImageSnapshot(
            textAndInputPrivacyLevel: textAndInputPrivacyLevel,
            imagePrivacyLevel: imagePrivacyLevel
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ImageSnapshotRequest {
    fileprivate init?(
        layerSnapshot: CALayerSnapshot,
        visibleFrame: CGRect,
        hasContentChanges: Bool,
        previousSnapshotData: ImageSnapshotData?
    ) {
        guard layerSnapshot.allowsImageSnapshot else {
            return nil
        }

        if layerSnapshot.layerClass == CALayer.self,
           layerSnapshot.contentsClass == nil,
           !hasContentChanges,
           previousSnapshotData == nil {
            return nil
        }

        self.init(
            replayID: layerSnapshot.replayID,
            layer: layerSnapshot.layer,
            layerClass: layerSnapshot.layerClass,
            bounds: layerSnapshot.bounds,
            absoluteFrame: layerSnapshot.absoluteFrame,
            visibleFrame: visibleFrame,
            isOpaque: layerSnapshot.isOpaque,
            hasContents: layerSnapshot.contentsClass != nil,
            hasContentChanges: hasContentChanges,
            textAndInputPrivacyLevel: layerSnapshot.textAndInputPrivacyLevel,
            imagePrivacyLevel: layerSnapshot.imagePrivacyLevel,
            previousSnapshotData: previousSnapshotData
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation {
    fileprivate func allowsImageSnapshot(
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel,
        imagePrivacyLevel: ImagePrivacyLevel
    ) -> Bool {
        switch semantics {
        case .image where imagePrivacyLevel == .maskNone:
            return true
        case .image(let image) where imagePrivacyLevel == .maskNonBundledOnly && image.isBundled:
            return true
        case .text(let text) where textAndInputPrivacyLevel == .maskSensitiveInputs && !text.isSecureTextEntry:
            return true
        case .textField(let textField) where textAndInputPrivacyLevel == .maskSensitiveInputs && !textField.isSecureTextEntry:
            return true
        case .layer, .activityIndicator, .progress, .stepper, .switchControl:
            return true
        default:
            return false
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservation.ImageSemantics {
    fileprivate var isBundled: Bool {
        guard let resolvedImage else {
            return false
        }
        return resolvedImage.description.contains("named(")
    }

    private var resolvedImage: UIImage? {
        isHighlighted ? highlightedImage ?? image : image
    }
}
#endif
