/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore
import Testing

@testable import DatadogSessionReplay

@MainActor
struct CALayerSnapshotPortalTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Resolves a position-matched portal and removes the original source subtree")
    func resolvesPositionMatchedPortalAndRemovesOriginalSourceSubtree() throws {
        // Given
        let sourceContent = CALayerSnapshot.mockWith(
            replayID: 3,
            absoluteFrame: CGRect(x: 28, y: 798, width: 346, height: 48)
        )
        let source = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 0, y: 0, width: 402, height: 874),
            transform: CATransform3DMakeRotation(.pi / 4, 0, 0, 1),
            opacity: 0.75,
            sublayers: [sourceContent]
        )
        let portal = CALayerSnapshot.mockWith(
            replayID: 4,
            absoluteFrame: sourceContent.absoluteFrame,
            observation: .portal(
                sourceReplayID: source.replayID,
                sourceRect: sourceContent.absoluteFrame,
                matchesPosition: true,
                matchesTransform: true,
                matchesOpacity: true
            ),
            masksToBounds: true,
            opacity: 0.25
        )
        let sourceContainer = CALayerSnapshot.mockWith(
            replayID: 5,
            absoluteFrame: CGRect(x: 0, y: 0, width: 402, height: 874),
            opacity: 0.5,
            sublayers: [source]
        )
        let root = CALayerSnapshot.mockRoot(
            absoluteFrame: CGRect(x: 0, y: 0, width: 402, height: 874),
            sublayers: [sourceContainer, portal]
        )

        // When
        let result = root.resolvingPortalLayers()

        // Then
        #expect(result.sublayers.map(\.replayID) == [sourceContainer.replayID, portal.replayID])
        #expect(result.sublayers.first?.sublayers.isEmpty == true)
        let resolvedPortal = try #require(result.sublayers.last)
        #expect(resolvedPortal.observation == .init(semantics: .layer))
        #expect(resolvedPortal.opacity == 0.25)
        #expect(resolvedPortal.masksToBounds)

        let resolvedSource = try #require(resolvedPortal.sublayers.first)
        #expect(resolvedSource.replayID == source.replayID)
        #expect(resolvedSource.absoluteFrame == source.absoluteFrame)
        #expect(resolvedSource.opacity == 0.75)
        #expect(resolvedSource.sublayers.map(\.replayID) == [sourceContent.replayID])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Positions unmatched portal content relative to the portal")
    func positionsUnmatchedPortalContentRelativeToPortal() throws {
        // Given
        let sourceContent = CALayerSnapshot.mockWith(
            replayID: 3,
            absoluteFrame: CGRect(x: 12, y: 24, width: 20, height: 10)
        )
        let source = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            opacity: 0.5,
            sublayers: [sourceContent]
        )
        let portal = CALayerSnapshot.mockWith(
            replayID: 4,
            absoluteFrame: CGRect(x: 200, y: 300, width: 100, height: 40),
            observation: .portal(
                sourceReplayID: source.replayID,
                sourceRect: source.bounds,
                matchesPosition: false,
                matchesTransform: false,
                matchesOpacity: false
            ),
            masksToBounds: false
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [source, portal])

        // When
        let result = root.resolvingPortalLayers()

        // Then
        let resolvedPortal = try #require(result.sublayers.first)
        #expect(!resolvedPortal.masksToBounds)

        let resolvedSource = try #require(resolvedPortal.sublayers.first)
        #expect(resolvedSource.absoluteFrame == portal.absoluteFrame)
        #expect(resolvedSource.contentGeometry.renderBounds == source.bounds)
        #expect(resolvedSource.contentGeometry.localRect == source.bounds)
        #expect(resolvedSource.contentGeometry.frame == portal.absoluteFrame)
        #expect(resolvedSource.opacity == 1)
        let resolvedContent = try #require(resolvedSource.sublayers.first)
        #expect(resolvedContent.absoluteFrame == CGRect(x: 202, y: 304, width: 20, height: 10))
        #expect(resolvedContent.contentGeometry.renderBounds == sourceContent.bounds)
        #expect(resolvedContent.contentGeometry.localRect == sourceContent.bounds)
        #expect(
            resolvedContent.contentGeometry.frame
                == CGRect(x: 202, y: 304, width: 20, height: 10)
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Omits portal content when its unmatched source transform cannot be represented")
    func omitsPortalContentForUnsupportedUnmatchedSourceTransform() throws {
        // Given
        let source = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            transform: CATransform3DMakeRotation(.pi / 4, 0, 0, 1)
        )
        let portal = CALayerSnapshot.mockWith(
            replayID: 3,
            absoluteFrame: CGRect(x: 200, y: 300, width: 100, height: 40),
            observation: .portal(
                sourceReplayID: source.replayID,
                sourceRect: source.bounds,
                matchesPosition: false,
                matchesTransform: false,
                matchesOpacity: false
            )
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [source, portal])

        // When
        let result = root.resolvingPortalLayers()

        // Then
        let unresolvedPortal = try #require(result.sublayers.first)
        #expect(unresolvedPortal.replayID == portal.replayID)
        #expect(
            unresolvedPortal.observation
                == .init(semantics: .visualEffect(.compositorSupport), ignoresSublayers: true)
        )
        #expect(unresolvedPortal.sublayers.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Stops resolving when portal sources form a cycle")
    func stopsResolvingPortalSourceCycles() throws {
        // Given
        let nestedPortal = CALayerSnapshot.mockWith(
            replayID: 3,
            observation: .portal(
                sourceReplayID: 2,
                sourceRect: .zero,
                matchesPosition: true,
                matchesTransform: true,
                matchesOpacity: true
            )
        )
        let source = CALayerSnapshot.mockWith(replayID: 2, sublayers: [nestedPortal])
        let portal = CALayerSnapshot.mockWith(
            replayID: 4,
            observation: .portal(
                sourceReplayID: source.replayID,
                sourceRect: .zero,
                matchesPosition: true,
                matchesTransform: true,
                matchesOpacity: true
            )
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [source, portal])

        // When
        let result = root.resolvingPortalLayers()

        // Then
        let resolvedPortal = try #require(result.sublayers.first)
        let resolvedSource = try #require(resolvedPortal.sublayers.first)
        let unresolvedNestedPortal = try #require(resolvedSource.sublayers.first)
        #expect(
            unresolvedNestedPortal.observation
                == .init(semantics: .visualEffect(.compositorSupport), ignoresSublayers: true)
        )
        #expect(unresolvedNestedPortal.sublayers.isEmpty)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension CALayerSnapshot.SemanticObservation {
    static func portal(
        sourceReplayID: Int64,
        sourceRect: CGRect,
        matchesPosition: Bool,
        matchesTransform: Bool,
        matchesOpacity: Bool
    ) -> Self {
        .init(
            semantics: .visualEffect(
                .portal(
                    .init(
                        sourceReplayID: sourceReplayID,
                        sourceRect: sourceRect,
                        matchesPosition: matchesPosition,
                        matchesTransform: matchesTransform,
                        matchesOpacity: matchesOpacity
                    )
                )
            ),
            ignoresSublayers: true
        )
    }
}
#endif
