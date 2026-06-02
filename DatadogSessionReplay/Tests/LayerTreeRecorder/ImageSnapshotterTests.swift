/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import Testing
import UIKit

@testable import DatadogSessionReplay

@MainActor
struct ImageSnapshotterTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Renders image snapshot for layer subclass")
    func rendersImageSnapshotForLayerSubclass() async throws {
        // Given
        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        layer.backgroundColor = UIColor.red.cgColor
        layer.contentsScale = 1
        let root = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let snapshotter = ImageSnapshotter()

        // When
        let results = await snapshotter.takeImageSnapshots(for: root, changeset: .init(), timeout: 1)

        // Then
        let result = try #require(results[root.replayID])
        let imageSnapshot = try result.get()
        #expect(imageSnapshot.frame == root.absoluteFrame)
        #expect(imageSnapshot.image.size == root.bounds.size)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Times out unprocessed image requests")
    func timesOutUnprocessedImageRequests() async throws {
        // Given
        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        let root = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let snapshotter = ImageSnapshotter()

        // When
        let results = await snapshotter.takeImageSnapshots(for: root, changeset: .init(), timeout: 0)

        // Then
        let result = try #require(results[root.replayID])
        #expect(throws: ImageSnapshotError.timedOut) {
            try result.get()
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Reuses cached image when only frame changes")
    func reusesCachedImageWhenOnlyFrameChanges() async throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let layer = CATextLayer()
        layer.frame = CGRect(x: 10, y: 10, width: 100, height: 40)
        layer.backgroundColor = UIColor.red.cgColor
        layer.contentsScale = 1
        rootLayer.addSublayer(layer)

        let snapshotter = ImageSnapshotter()
        let firstRoot = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let firstResults = await snapshotter.takeImageSnapshots(for: firstRoot, changeset: .init(), timeout: 1)
        let firstResult = try #require(firstResults[layer.replayID])
        let firstImageSnapshot = try firstResult.get()

        // When
        layer.frame = CGRect(x: 20, y: 15, width: 100, height: 40)
        let secondRoot = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let secondResults = await snapshotter.takeImageSnapshots(for: secondRoot, changeset: .init(), timeout: 1)

        // Then
        let secondResult = try #require(secondResults[layer.replayID])
        let secondImageSnapshot = try secondResult.get()
        #expect(firstImageSnapshot.image === secondImageSnapshot.image)
        #expect(secondImageSnapshot.frame == CGRect(x: 20, y: 15, width: 100, height: 40))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Renders new image when content changes")
    func rendersNewImageWhenContentChanges() async throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let layer = CATextLayer()
        layer.frame = CGRect(x: 10, y: 10, width: 100, height: 40)
        layer.backgroundColor = UIColor.red.cgColor
        layer.contentsScale = 1
        rootLayer.addSublayer(layer)

        let snapshotter = ImageSnapshotter()
        let firstRoot = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let firstResults = await snapshotter.takeImageSnapshots(for: firstRoot, changeset: .init(), timeout: 1)
        let firstResult = try #require(firstResults[layer.replayID])
        let firstImageSnapshot = try firstResult.get()

        // When
        layer.backgroundColor = UIColor.blue.cgColor
        let secondRoot = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let changeset = CALayerChangeset.mockChange(for: layer, aspects: .display)
        let secondResults = await snapshotter.takeImageSnapshots(for: secondRoot, changeset: changeset, timeout: 1)

        // Then
        let secondResult = try #require(secondResults[layer.replayID])
        let secondImageSnapshot = try secondResult.get()
        #expect(firstImageSnapshot.image !== secondImageSnapshot.image)
        #expect(secondImageSnapshot.frame == layer.frame)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Renders full layer image when clipped by ancestor")
    func rendersFullLayerImageWhenClippedByAncestor() async throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let clippingLayer = CALayer()
        clippingLayer.frame = CGRect(x: 10, y: 10, width: 40, height: 40)
        clippingLayer.masksToBounds = true
        rootLayer.addSublayer(clippingLayer)

        let layer = CATextLayer()
        layer.frame = CGRect(x: 20, y: 20, width: 40, height: 40)
        layer.backgroundColor = UIColor.red.cgColor
        layer.contentsScale = 1
        clippingLayer.addSublayer(layer)

        let root = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let snapshotter = ImageSnapshotter()

        // When
        let results = await snapshotter.takeImageSnapshots(for: root, changeset: .init(), timeout: 1)

        // Then
        let result = try #require(results[layer.replayID])
        let imageSnapshot = try result.get()
        #expect(imageSnapshot.frame == CGRect(x: 30, y: 30, width: 40, height: 40))
        #expect(imageSnapshot.image.size == CGSize(width: 40, height: 40))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Renders visible rect for oversized layer")
    func rendersVisibleRectForOversizedLayer() async throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let layer = CATextLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        layer.backgroundColor = UIColor.red.cgColor
        layer.contentsScale = 1
        rootLayer.addSublayer(layer)

        let root = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let snapshotter = ImageSnapshotter()

        // When
        let results = await snapshotter.takeImageSnapshots(for: root, changeset: .init(), timeout: 1)

        // Then
        let result = try #require(results[layer.replayID])
        let imageSnapshot = try result.get()
        #expect(imageSnapshot.frame == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(imageSnapshot.image.size == CGSize(width: 100, height: 100))
    }
}
#endif
