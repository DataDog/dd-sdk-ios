/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import Testing

@testable import DatadogSessionReplay

@MainActor
struct LayerImageRendererTests {
    @available(iOS 13.0, tvOS 13.0, *)
    enum Fixtures {
        static let rootBounds = CGRect(x: 0, y: 0, width: 200, height: 300)

        static var rootLayer: CALayer {
            let layer = CALayer()
            layer.bounds = rootBounds
            return layer
        }

        static func layerSnapshot(
            for layer: CALayer,
            replayID: Int64,
            in rootLayer: CALayer,
            hasContents: Bool = false,
            clipRect: CGRect? = nil,
            semantics: LayerSnapshot.Semantics = .generic
        ) -> LayerSnapshot {
            LayerSnapshotTests.Fixtures.snapshot(
                layer: layer,
                replayID: replayID,
                frame: layer.convert(layer.bounds, to: rootLayer),
                clipRect: clipRect ?? rootLayer.bounds,
                hasContents: hasContents,
                semantics: semantics
            )
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func plainLayerWithoutContentsAndNoChangesIsFilteredOut() async {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 60)
        rootLayer.addSublayer(layer)

        let snapshot = Fixtures.layerSnapshot(for: layer, replayID: 1, in: rootLayer, hasContents: false)
        let renderer = LayerImageRenderer(scale: 1, timeSource: .constant(0))

        // when
        let results = await renderer.renderImages(
            for: [snapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        #expect(results.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func plainLayerWithContentsRendersImage() async throws {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let snapshot = Fixtures.layerSnapshot(for: layer, replayID: 2, in: rootLayer, hasContents: true)
        let renderer = LayerImageRenderer(scale: 1, timeSource: .constant(0))

        // when
        let results = await renderer.renderImages(
            for: [snapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        let image = try results.image(for: snapshot.replayID)
        #expect(image.frame.equalTo(snapshot.frame))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func reusesCachedImageWhenNewRenderIsNotNeeded() async throws {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let firstSnapshot = Fixtures.layerSnapshot(for: layer, replayID: 3, in: rootLayer, hasContents: true)
        let secondSnapshot = Fixtures.layerSnapshot(for: layer, replayID: 3, in: rootLayer, hasContents: false)

        let renderer = LayerImageRenderer(scale: 1, timeSource: .constant(0))

        let firstResults = await renderer.renderImages(
            for: [firstSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // when
        let secondResults = await renderer.renderImages(
            for: [secondSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        let firstImage = try firstResults.image(for: firstSnapshot.replayID)
        let secondImage = try secondResults.image(for: secondSnapshot.replayID)

        #expect(firstImage === secondImage)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func rerendersPartialImageWhenVisibleRectChangesWithinCachedRect() async throws {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 400, height: 120)
        layer.position = CGPoint(x: 200, y: 60)
        rootLayer.addSublayer(layer)

        let firstSnapshot = Fixtures.layerSnapshot(
            for: layer,
            replayID: 8,
            in: rootLayer,
            hasContents: true,
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 120)
        )
        let secondSnapshot = Fixtures.layerSnapshot(
            for: layer,
            replayID: 8,
            in: rootLayer,
            hasContents: false,
            clipRect: CGRect(x: 60, y: 0, width: 120, height: 120)
        )

        let renderer = LayerImageRenderer(scale: 1, timeSource: .constant(0))

        let firstResults = await renderer.renderImages(
            for: [firstSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // when
        let secondResults = await renderer.renderImages(
            for: [secondSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        let firstImage = try firstResults.image(for: firstSnapshot.replayID)
        let secondImage = try secondResults.image(for: secondSnapshot.replayID)

        #expect(firstImage !== secondImage)
        #expect(secondImage.frame.equalTo(CGRect(x: 60, y: 0, width: 120, height: 120)))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func reusesCachedResourceAndCachesUpdatedFrameWhenGeometryChanges() async throws {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        layer.position = CGPoint(x: 60, y: 40)
        rootLayer.addSublayer(layer)

        let firstSnapshot = Fixtures.layerSnapshot(for: layer, replayID: 9, in: rootLayer)
        let renderer = LayerImageRenderer(scale: 1, timeSource: .constant(0))

        let firstResults = await renderer.renderImages(
            for: [firstSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        layer.position = CGPoint(x: 100, y: 90)
        let secondSnapshot = Fixtures.layerSnapshot(for: layer, replayID: 9, in: rootLayer)

        // when
        let secondResults = await renderer.renderImages(
            for: [secondSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )
        let thirdResults = await renderer.renderImages(
            for: [secondSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        let firstImage = try firstResults.image(for: firstSnapshot.replayID)
        let secondImage = try secondResults.image(for: secondSnapshot.replayID)
        let thirdImage = try thirdResults.image(for: secondSnapshot.replayID)

        #expect(firstImage !== secondImage)
        #expect(secondImage.frame.equalTo(secondSnapshot.frame))
        #expect(secondImage === thirdImage)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func reusesCachedImageWhenLayerReappearsBeforeExpiration() async throws {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let firstSnapshot = Fixtures.layerSnapshot(for: layer, replayID: 30, in: rootLayer, hasContents: true)
        let secondSnapshot = Fixtures.layerSnapshot(for: layer, replayID: 30, in: rootLayer, hasContents: false)

        let renderer = LayerImageRenderer(
            scale: 1,
            timeSource: .constant(0),
            cachePolicy: .init(expirationFrameCount: 5, evictionIntervalFrameCount: 10, maximumEvictions: 128)
        )

        let firstResults = await renderer.renderImages(
            for: [firstSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        _ = await renderer.renderImages(
            for: [],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // when
        let secondResults = await renderer.renderImages(
            for: [secondSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        let firstImage = try firstResults.image(for: firstSnapshot.replayID)
        let secondImage = try secondResults.image(for: secondSnapshot.replayID)

        #expect(firstImage === secondImage)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func evictsCachedStateAfterExpirationFrameCount() async {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let initialSnapshot = Fixtures.layerSnapshot(for: layer, replayID: 31, in: rootLayer, hasContents: true)
        let reusedSnapshot = Fixtures.layerSnapshot(for: layer, replayID: 31, in: rootLayer, hasContents: false)

        let renderer = LayerImageRenderer(
            scale: 1,
            timeSource: .constant(0),
            cachePolicy: .init(expirationFrameCount: 1, evictionIntervalFrameCount: 1, maximumEvictions: 128)
        )

        _ = await renderer.renderImages(
            for: [initialSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        _ = await renderer.renderImages(
            for: [],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )
        _ = await renderer.renderImages(
            for: [],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // when
        let results = await renderer.renderImages(
            for: [reusedSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        #expect(results.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func evictsCacheOnlyOnEvictionIntervalFrames() async throws {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let firstSnapshot = Fixtures.layerSnapshot(for: layer, replayID: 32, in: rootLayer, hasContents: true)
        let secondSnapshot = Fixtures.layerSnapshot(for: layer, replayID: 32, in: rootLayer, hasContents: false)

        let renderer = LayerImageRenderer(
            scale: 1,
            timeSource: .constant(0),
            cachePolicy: .init(expirationFrameCount: 0, evictionIntervalFrameCount: 3, maximumEvictions: 128)
        )

        let firstResults = await renderer.renderImages(
            for: [firstSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        _ = await renderer.renderImages(
            for: [],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // when
        let secondResults = await renderer.renderImages(
            for: [secondSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        let firstImage = try firstResults.image(for: firstSnapshot.replayID)
        let secondImage = try secondResults.image(for: secondSnapshot.replayID)

        #expect(firstImage === secondImage)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func marksRemainingCandidatesTimedOutWhenBudgetIsExceeded() async throws {
        // given
        let rootLayer = Fixtures.rootLayer

        let firstLayer = CALayer()
        firstLayer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(firstLayer)

        let secondLayer = CALayer()
        secondLayer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(secondLayer)

        let firstSnapshot = Fixtures.layerSnapshot(for: firstLayer, replayID: 4, in: rootLayer, hasContents: true)
        let secondSnapshot = Fixtures.layerSnapshot(for: secondLayer, replayID: 5, in: rootLayer, hasContents: true)
        let renderer = LayerImageRenderer(scale: 1, timeSource: .sequence([0, 0, 0.2]))

        // when
        let results = await renderer.renderImages(
            for: [firstSnapshot, secondSnapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 0.1
        )

        // then
        #expect(results.count == 2)

        _ = try results.image(for: firstSnapshot.replayID)
        #expect(results[secondSnapshot.replayID]?.layerImageError == .timedOut)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func marksRenderingErrorsAsDiscarded() async {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 60)
        rootLayer.addSublayer(layer)

        let snapshot = LayerSnapshotTests.Fixtures.snapshot(
            layer: layer,
            replayID: 6,
            frame: CGRect(x: 500, y: 500, width: 100, height: 60), // outside clip rect -> invalid visible rect
            clipRect: rootLayer.bounds,
            hasContents: true
        )

        let renderer = LayerImageRenderer(scale: 1, timeSource: .constant(0))

        // when
        let results = await renderer.renderImages(
            for: [snapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        #expect(results[snapshot.replayID]?.layerImageError == .discarded)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func layerSubclassWithoutContentsIsImageCandidate() async throws {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let renderer = LayerImageRenderer(scale: 1, timeSource: .constant(0))
        let snapshot = Fixtures.layerSnapshot(for: layer, replayID: 7, in: rootLayer, hasContents: false)

        // when
        let results = await renderer.renderImages(
            for: [snapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        _ = try results.image(for: snapshot.replayID)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func webViewSemanticSnapshotIsNotImageCandidate() async {
        // given
        let rootLayer = Fixtures.rootLayer
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 80)
        rootLayer.addSublayer(layer)

        let renderer = LayerImageRenderer(scale: 1, timeSource: .constant(0))
        let snapshot = Fixtures.layerSnapshot(
            for: layer,
            replayID: 11,
            in: rootLayer,
            hasContents: true,
            semantics: .webView(slotID: 42)
        )

        // when
        let results = await renderer.renderImages(
            for: [snapshot],
            changes: .init(),
            rootLayer: .init(rootLayer),
            timeoutInterval: 1
        )

        // then
        #expect(results.isEmpty)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension Dictionary where Key == Int64, Value == LayerImageRenderer.Result {
    fileprivate func image(for replayID: Int64) throws -> LayerImage {
        let result = try #require(self[replayID])
        return try result.get()
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension Result where Success == LayerImage, Failure == LayerImageError {
    fileprivate var layerImageError: LayerImageError? {
        guard case .failure(let error) = self else {
            return nil
        }
        return error
    }
}
#endif
