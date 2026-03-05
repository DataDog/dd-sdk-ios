/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import Testing
import UIKit

@_spi(Internal)
@testable import DatadogSessionReplay

@MainActor
struct LayerWireframeBuilderTests {
    @available(iOS 13.0, tvOS 13.0, *)
    enum Fixtures {
        static let visibleFrame = CGRect(x: 10, y: 20, width: 100, height: 40)
        static let clipRect = CGRect(x: 0, y: 0, width: 200, height: 300)

        static func snapshot(
            replayID: Int64 = 1,
            semantics: LayerSnapshot.Semantics = .generic,
            backgroundColor: CGColor? = nil,
            borderWidth: CGFloat = 0,
            borderColor: CGColor? = nil
        ) -> LayerSnapshot {
            LayerSnapshotTests.Fixtures.snapshot(
                replayID: replayID,
                frame: visibleFrame,
                clipRect: clipRect,
                backgroundColor: backgroundColor,
                semantics: semantics,
                borderWidth: borderWidth,
                borderColor: borderColor
            )
        }

        static func layerImage(frame: CGRect = visibleFrame) -> LayerImage {
            let image = UIImage(cgImage: LayerSnapshotTests.Fixtures.anyImage)
            return LayerImage(resource: .init(image: image, tintColor: nil), frame: frame)
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func createsImageWireframeAndCollectsResourceForRenderedLayerImage() throws {
        // given
        let snapshot = Fixtures.snapshot(replayID: 10)
        let layerImage = Fixtures.layerImage()
        let builder = LayerWireframeBuilder()

        // when
        let output = builder.createWireframes(
            for: [snapshot],
            layerImages: [snapshot.replayID: .success(layerImage)],
            webViewSlotIDs: []
        )

        // then
        let wireframe = try #require(output.wireframes.first?.imageWireframe)

        #expect(wireframe.id == snapshot.replayID)
        #expect(wireframe.x == Int64.ddWithNoOverflow(layerImage.frame.minX))
        #expect(wireframe.y == Int64.ddWithNoOverflow(layerImage.frame.minY))
        #expect(output.resources.count == 1)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func createsPlaceholderWireframeForTimedOutImage() throws {
        // given
        let snapshot = Fixtures.snapshot(replayID: 11)
        let builder = LayerWireframeBuilder()

        // when
        let output = builder.createWireframes(
            for: [snapshot],
            layerImages: [snapshot.replayID: .failure(.timedOut)],
            webViewSlotIDs: []
        )

        // then
        let wireframe = try #require(output.wireframes.first?.placeholderWireframe)

        #expect(wireframe.id == snapshot.replayID)
        #expect(wireframe.label == LayerWireframeBuilder.timedOutLabel)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func createsNoWireframesForDiscardedImageSnapshots() {
        // given
        let snapshot = Fixtures.snapshot(replayID: 12)
        let builder = LayerWireframeBuilder()

        // when
        let output = builder.createWireframes(
            for: [snapshot],
            layerImages: [snapshot.replayID: .failure(.discarded)],
            webViewSlotIDs: []
        )

        // then
        #expect(output.wireframes.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func createsShapeWireframeWhenImageResultIsMissingAndShapeAppearanceIsVisible() throws {
        // given
        let snapshot = Fixtures.snapshot(
            replayID: 13,
            backgroundColor: UIColor.red.cgColor
        )
        let builder = LayerWireframeBuilder()

        // when
        let output = builder.createWireframes(
            for: [snapshot],
            layerImages: [:],
            webViewSlotIDs: []
        )

        // then
        let wireframe = try #require(output.wireframes.first?.shapeWireframe)

        #expect(wireframe.id == snapshot.replayID)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func createsNoWireframesWhenImageResultIsMissingAndShapeAppearanceIsNotVisible() {
        // given
        let snapshot = Fixtures.snapshot(replayID: 14)
        let builder = LayerWireframeBuilder()

        // when
        let output = builder.createWireframes(
            for: [snapshot],
            layerImages: [:],
            webViewSlotIDs: []
        )

        // then
        #expect(output.wireframes.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func createsVisibleAndHiddenWebViewWireframes() throws {
        // given
        let snapshot = Fixtures.snapshot(replayID: 15, semantics: .webView(slotID: 42))
        let builder = LayerWireframeBuilder()

        // when
        let output = builder.createWireframes(
            for: [snapshot],
            layerImages: [:],
            webViewSlotIDs: [42, 84]
        )

        // then
        #expect(output.wireframes.count == 2)

        let hidden = try #require(output.wireframes[0].webviewWireframe)
        #expect(hidden.id == 84)
        #expect(hidden.isVisible == false)

        let visible = try #require(output.wireframes[1].webviewWireframe)
        #expect(visible.id == 42)
        #expect(visible.isVisible == true)
    }
}

extension SRWireframe {
    fileprivate var imageWireframe: SRImageWireframe? {
        guard case let .imageWireframe(wireframe) = self else {
            return nil
        }
        return wireframe
    }

    fileprivate var placeholderWireframe: SRPlaceholderWireframe? {
        guard case let .placeholderWireframe(wireframe) = self else {
            return nil
        }
        return wireframe
    }

    fileprivate var shapeWireframe: SRShapeWireframe? {
        guard case let .shapeWireframe(wireframe) = self else {
            return nil
        }
        return wireframe
    }

    fileprivate var webviewWireframe: SRWebviewWireframe? {
        guard case let .webviewWireframe(wireframe) = self else {
            return nil
        }
        return wireframe
    }
}
#endif
