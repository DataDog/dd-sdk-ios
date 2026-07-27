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
    /// Replaces supported portal layers with their hidden source layer hierarchy.
    func resolvingPortalLayers() -> CALayerSnapshot {
        var resolver = PortalLayerResolver(root: self)
        return resolver.resolve()
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private struct PortalLayerResolver {
    typealias PortalSemantics = CALayerSnapshot.SemanticObservation.PortalSemantics

    private let root: CALayerSnapshot
    private let identifiedSnapshots: [Int64: CALayerSnapshot]
    private let hiddenSourceReplayIDs: Set<Int64>

    private var claimedSourceReplayIDs: Set<Int64> = []
    private var resolvingSourceReplayIDs: Set<Int64> = []

    init(root: CALayerSnapshot) {
        var identifiedSnapshots: [Int64: CALayerSnapshot] = [:]
        var hiddenSourceReplayIDs: Set<Int64> = []
        var pendingSnapshots = [root]

        while let snapshot = pendingSnapshots.popLast() {
            identifiedSnapshots[snapshot.replayID] = snapshot

            if case .visualEffect(.portal(let portal)) = snapshot.observation.semantics {
                hiddenSourceReplayIDs.insert(portal.sourceReplayID)
            }

            for sublayer in snapshot.sublayers {
                pendingSnapshots.append(sublayer)
            }
        }

        self.root = root
        self.identifiedSnapshots = identifiedSnapshots
        self.hiddenSourceReplayIDs = hiddenSourceReplayIDs
    }

    mutating func resolve() -> CALayerSnapshot {
        guard !hiddenSourceReplayIDs.isEmpty else {
            return root
        }

        return resolveContents(of: root)
    }

    private mutating func resolveVisible(_ snapshot: CALayerSnapshot) -> CALayerSnapshot? {
        guard !hiddenSourceReplayIDs.contains(snapshot.replayID) else {
            return nil
        }

        return resolveContents(of: snapshot)
    }

    private mutating func resolveContents(of snapshot: CALayerSnapshot) -> CALayerSnapshot {
        guard case .visualEffect(.portal(let portal)) = snapshot.observation.semantics else {
            var result = snapshot
            result.sublayers = snapshot.sublayers.compactMap {
                resolveVisible($0)
            }
            return result
        }

        return resolvePortal(snapshot, semantics: portal)
    }

    private mutating func resolvePortal(
        _ snapshot: CALayerSnapshot,
        semantics portal: PortalSemantics
    ) -> CALayerSnapshot {
        guard
            portal.sourceReplayID != snapshot.replayID,
            !resolvingSourceReplayIDs.contains(portal.sourceReplayID),
            var source = identifiedSnapshots[portal.sourceReplayID]
        else {
            return resolveAsCompositorSupport(snapshot)
        }

        // Root-relative frames already contain the source transform. Without a matching
        // transform, non-identity source geometry cannot be reconstructed from the snapshot.
        guard portal.matchesTransform || CATransform3DIsIdentity(source.transform) else {
            return resolveAsCompositorSupport(snapshot)
        }

        // Resolving the same source into multiple portals is not yet supported.
        guard claimedSourceReplayIDs.insert(portal.sourceReplayID).inserted else {
            return resolveAsCompositorSupport(snapshot)
        }

        resolvingSourceReplayIDs.insert(portal.sourceReplayID)
        defer { resolvingSourceReplayIDs.remove(portal.sourceReplayID) }

        source = resolveContents(of: source)

        if !portal.matchesPosition {
            guard source.move(
                contentsFrom: portal.sourceRect,
                to: snapshot.absoluteFrame
            ) else {
                return resolveAsCompositorSupport(snapshot)
            }
        }

        if !portal.matchesOpacity {
            source.opacity = 1
        }

        var result = snapshot
        result.observation = .init(semantics: .layer)
        result.sublayers = [source]
        return result
    }

    private func resolveAsCompositorSupport(_ snapshot: CALayerSnapshot) -> CALayerSnapshot {
        var result = snapshot
        result.observation = .init(
            semantics: .visualEffect(.compositorSupport),
            ignoresSublayers: true
        )
        result.sublayers = []
        return result
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    fileprivate mutating func move(contentsFrom sourceRect: CGRect, to destinationFrame: CGRect) -> Bool {
        guard sourceRect.size == destinationFrame.size else {
            return false
        }

        let sourceOrigin = CGPoint(
            x: absoluteFrame.minX + sourceRect.minX - bounds.minX,
            y: absoluteFrame.minY + sourceRect.minY - bounds.minY
        )
        offsetAbsoluteFrames(
            x: destinationFrame.minX - sourceOrigin.x,
            y: destinationFrame.minY - sourceOrigin.y
        )
        return true
    }

    private mutating func offsetAbsoluteFrames(x: CGFloat, y: CGFloat) {
        absoluteFrame = absoluteFrame.offsetBy(dx: x, dy: y)
        contentGeometry.frame = contentGeometry.frame.offsetBy(dx: x, dy: y)

        if case .webView(let webView) = observation.semantics {
            observation.semantics = .webView(
                .init(
                    slotID: webView.slotID,
                    slotFrame: webView.slotFrame.offsetBy(dx: x, dy: y)
                )
            )
        }

        for index in sublayers.indices {
            sublayers[index].offsetAbsoluteFrames(x: x, y: y)
        }
    }
}
#endif
