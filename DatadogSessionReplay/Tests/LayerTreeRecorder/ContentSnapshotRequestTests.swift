/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import QuartzCore
import TestUtilities
import Testing
import UIKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct ContentSnapshotRequestTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Throws when layer reference is deallocated")
    func throwsWhenLayerReferenceIsDeallocated() {
        // Given
        let request: ContentSnapshotRequest = {
            var layer: CALayer? = CALayer()
            let request = ContentSnapshotRequest.mockAny(layer: layer!)
            layer = nil
            return request
        }()

        // When / Then
        #expect(throws: ImageSnapshotRequestResolutionError.missingLayer) {
            _ = try request.resolved()
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Throws when local rect is empty")
    func throwsWhenLocalRectIsEmpty() {
        // Given
        let layer = CALayer()
        let request = ContentSnapshotRequest.mockAny(
            layer: layer,
            geometry: .init(renderBounds: layer.bounds, localRect: .zero, frame: .zero)
        )

        // When / Then
        #expect(throws: ImageSnapshotRequestResolutionError.invalidRect) {
            _ = try request.resolved()
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("New plain layer with contents needs snapshot")
    func newPlainLayerWithContentsNeedsSnapshot() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let request = ContentSnapshotRequest.mockAny(layer: layer, hasContents: true)

        // When
        let resolvedRequest = try request.resolved()

        // Then
        #expect(resolvedRequest.layer === layer)
        #expect(resolvedRequest.geometry.localRect == layer.bounds)
        #expect(resolvedRequest.needsSnapshot)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Plain layer with contents does not need snapshot after first appearance")
    func plainLayerWithContentsDoesNotNeedSnapshotAfterFirstAppearance() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let request = ContentSnapshotRequest.mockAny(
            layer: layer,
            hasContents: true,
            previousSnapshotData: .mockAny(localRect: layer.bounds, bounds: layer.bounds)
        )

        // When
        let resolvedRequest = try request.resolved()

        // Then
        #expect(resolvedRequest.geometry.localRect == layer.bounds)
        #expect(resolvedRequest.needsSnapshot == false)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Layer with content changes needs snapshot")
    func layerWithContentChangesNeedsSnapshot() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let request = ContentSnapshotRequest.mockAny(
            layer: layer,
            hasChanges: true,
            previousSnapshotData: .mockAny(localRect: layer.bounds, bounds: layer.bounds)
        )

        // When
        let resolvedRequest = try request.resolved()

        // Then
        #expect(resolvedRequest.geometry.localRect == layer.bounds)
        #expect(resolvedRequest.needsSnapshot)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Layer subclass without changes does not need snapshot after first appearance")
    func layerSubclassWithoutChangesDoesNotNeedSnapshotAfterFirstAppearance() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let request = ContentSnapshotRequest.mockAny(
            layer: layer,
            previousSnapshotData: .mockAny(localRect: layer.bounds, bounds: layer.bounds)
        )

        // When
        let resolvedRequest = try request.resolved()

        // Then
        #expect(resolvedRequest.geometry.localRect == layer.bounds)
        #expect(resolvedRequest.needsSnapshot == false)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Layer subclass needs snapshot when bounds change")
    func layerSubclassNeedsSnapshotWhenBoundsChange() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let previousBounds = CGRect(x: 0, y: 0, width: 80, height: 40)
        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let request = ContentSnapshotRequest.mockAny(
            layer: layer,
            previousSnapshotData: .mockAny(localRect: previousBounds, bounds: previousBounds)
        )

        // When
        let resolvedRequest = try request.resolved()

        // Then
        #expect(resolvedRequest.geometry.localRect == layer.bounds)
        #expect(resolvedRequest.needsSnapshot)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Layer subclass with geometry animation does not need snapshot")
    func layerSubclassWithGeometryAnimationDoesNotNeedSnapshot() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        layer.add(CABasicAnimation(keyPath: "position"), forKey: "position")
        rootLayer.addSublayer(layer)

        let request = ContentSnapshotRequest.mockAny(
            layer: layer,
            previousSnapshotData: .mockAny(localRect: layer.bounds, bounds: layer.bounds)
        )

        // When
        let resolvedRequest = try request.resolved()

        // Then
        #expect(resolvedRequest.geometry.localRect == layer.bounds)
        #expect(resolvedRequest.needsSnapshot == false)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Uses captured frame when live layer moves before resolution")
    func usesCapturedFrameWhenLiveLayerMovesBeforeResolution() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let capturedFrame = CGRect(x: 10, y: 20, width: 100, height: 40)
        let layer = CALayer()
        layer.frame = capturedFrame
        rootLayer.addSublayer(layer)

        let request = ContentSnapshotRequest.mockAny(layer: layer)

        layer.frame = CGRect(x: 30, y: 40, width: 100, height: 40)

        // When
        let resolvedRequest = try request.resolved()

        // Then
        #expect(resolvedRequest.geometry.frame == capturedFrame)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Partial snapshot needs snapshot when local rect changes")
    func partialSnapshotNeedsSnapshotWhenLocalRectChanges() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 400, height: 120)
        layer.position = CGPoint(x: 200, y: 60)
        rootLayer.addSublayer(layer)

        let localRect = CGRect(x: 180, y: 0, width: 20, height: 100)
        let request = ContentSnapshotRequest.mockAny(
            layer: layer,
            geometry: .init(renderBounds: layer.bounds, localRect: localRect, frame: localRect),
            previousSnapshotData: .mockAny(
                localRect: CGRect(x: 0, y: 0, width: 10, height: 100),
                bounds: layer.bounds
            )
        )

        // When
        let resolvedRequest = try request.resolved()

        // Then
        #expect(resolvedRequest.geometry.localRect == localRect)
        #expect(resolvedRequest.geometry.frame == localRect)
        #expect(resolvedRequest.needsSnapshot)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Partial snapshot does not need snapshot when local rect is unchanged")
    func partialSnapshotDoesNotNeedSnapshotWhenLocalRectIsUnchanged() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 400, height: 120)
        layer.position = CGPoint(x: 200, y: 60)
        rootLayer.addSublayer(layer)

        let localRect = CGRect(x: 180, y: 0, width: 20, height: 100)
        let request = ContentSnapshotRequest.mockAny(
            layer: layer,
            geometry: .init(renderBounds: layer.bounds, localRect: localRect, frame: localRect),
            previousSnapshotData: .mockAny(
                localRect: localRect,
                bounds: layer.bounds
            )
        )

        // When
        let resolvedRequest = try request.resolved()

        // Then
        #expect(resolvedRequest.geometry.localRect == localRect)
        #expect(resolvedRequest.geometry.frame == localRect)
        #expect(resolvedRequest.needsSnapshot == false)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ContentSnapshotRequest {
    @MainActor
    fileprivate static func mockAny(
        layer: CALayer,
        geometry: CALayerSnapshot.ContentGeometry? = nil,
        hasContents: Bool = false,
        dependencies: [CALayerReference] = [],
        hasChanges: Bool = false,
        previousSnapshotData: ContentSnapshotData? = nil
    ) -> ContentSnapshotRequest {
        ContentSnapshotRequest(
            replayID: layer.replayID,
            layer: CALayerReference(layer),
            layerClass: type(of: layer),
            delegateClass: layer.delegate.map { type(of: $0) },
            hasLayerSemantics: true,
            bounds: layer.bounds,
            geometry: geometry ?? .init(
                renderBounds: layer.bounds,
                localRect: layer.bounds,
                frame: layer.frame
            ),
            isOpaque: layer.isOpaque,
            hasContents: hasContents,
            dependencies: dependencies,
            hasChanges: hasChanges,
            textAndInputPrivacyLevel: .maskAll,
            imagePrivacyLevel: .maskAll,
            previousSnapshotData: previousSnapshotData
        )
    }
}

#endif
