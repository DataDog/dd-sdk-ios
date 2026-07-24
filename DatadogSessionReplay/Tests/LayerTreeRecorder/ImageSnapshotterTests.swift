/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import TestUtilities
import Testing
import UIKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
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
        let result = try #require(results.contentSnapshots[root.replayID])
        let imageSnapshot = try result.get()
        #expect(imageSnapshot.frame == root.absoluteFrame)
        #expect(imageSnapshot.image.size == root.bounds.size)
        #expect(imageSnapshot.layerClass == root.layerClass)
        #expect(imageSnapshot.delegateClass == root.delegateClass)
        #expect(imageSnapshot.hasLayerSemantics)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Renders ignored sublayer content outside its semantic owner bounds")
    func rendersIgnoredSublayerContentOutsideSemanticOwnerBounds() async throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 40, y: 40, width: 20, height: 20)
        imageView.layer.contentsScale = 1
        rootLayer.addSublayer(imageView.layer)

        let dependency = CALayer()
        dependency.frame = CGRect(x: -5, y: -5, width: 30, height: 30)
        dependency.backgroundColor = UIColor.red.cgColor
        imageView.layer.addSublayer(dependency)

        let root = try #require(
            CALayerSnapshot(from: rootLayer, in: .mockAny(imagePrivacyLevel: .maskNone))
        )
        let snapshotter = ImageSnapshotter()

        // When
        let results = await snapshotter.takeImageSnapshots(for: root, changeset: .init(), timeout: 1)

        // Then
        let result = try #require(results.contentSnapshots[imageView.layer.replayID])
        let imageSnapshot = try result.get()
        #expect(imageSnapshot.frame == CGRect(x: 35, y: 35, width: 30, height: 30))
        #expect(imageSnapshot.image.size == CGSize(width: 30, height: 30))
        let cornerImage = imageSnapshot.image.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(cornerImage.map { UIImage(cgImage: $0) }?.dominantColor == .red)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Renders and caches mask snapshot for container mask")
    func rendersAndCachesMaskSnapshotForContainerMask() async throws {
        // Given
        let fixture = MaskFixture()
        let snapshotter = ImageSnapshotter()

        let firstRoot = try #require(CALayerSnapshot(from: fixture.rootLayer, in: .mockAny()))
        let firstResults = await snapshotter.takeImageSnapshots(for: firstRoot, changeset: .init(), timeout: 1)
        let firstResult = try #require(firstResults.maskSnapshots[fixture.mask.replayID])
        let firstMaskSnapshot = try firstResult.get()

        // When
        let secondRoot = try #require(CALayerSnapshot(from: fixture.rootLayer, in: .mockAny()))
        let secondResults = await snapshotter.takeImageSnapshots(for: secondRoot, changeset: .init(), timeout: 1)

        // Then
        let secondResult = try #require(secondResults.maskSnapshots[fixture.mask.replayID])
        let secondMaskSnapshot = try secondResult.get()
        #expect(firstMaskSnapshot === secondMaskSnapshot)
        #expect(secondMaskSnapshot.image.size == fixture.maskedLayer.bounds.size)

        // When
        fixture.maskChild.backgroundColor = UIColor.white.cgColor
        let changedRoot = try #require(CALayerSnapshot(from: fixture.rootLayer, in: .mockAny()))
        let changeset = CALayerChangeset.mockChange(for: fixture.maskChild, aspects: .display)
        let changedResults = await snapshotter.takeImageSnapshots(for: changedRoot, changeset: changeset, timeout: 1)

        // Then
        let changedResult = try #require(changedResults.maskSnapshots[fixture.mask.replayID])
        let changedMaskSnapshot = try changedResult.get()
        #expect(changedMaskSnapshot !== firstMaskSnapshot)
        #expect(changedMaskSnapshot.image.size == fixture.maskedLayer.bounds.size)
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
        let result = try #require(results.contentSnapshots[root.replayID])
        #expect(throws: ImageSnapshotError.timedOut) {
            try result.get()
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Removes cached image when changed request times out")
    func removesCachedImageWhenChangedRequestTimesOut() async throws {
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
        let firstResult = try #require(firstResults.contentSnapshots[layer.replayID])
        let firstImageSnapshot = try firstResult.get()

        layer.backgroundColor = UIColor.blue.cgColor
        let changedRoot = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let changeset = CALayerChangeset.mockChange(for: layer, aspects: .display)

        // When
        let timedOutResults = await snapshotter.takeImageSnapshots(for: changedRoot, changeset: changeset, timeout: 0)
        let timedOutResult = try #require(timedOutResults.contentSnapshots[layer.replayID])

        // Then
        #expect(throws: ImageSnapshotError.timedOut) {
            try timedOutResult.get()
        }

        let nextRoot = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let nextResults = await snapshotter.takeImageSnapshots(for: nextRoot, changeset: .init(), timeout: 1)
        let nextResult = try #require(nextResults.contentSnapshots[layer.replayID])
        let nextImageSnapshot = try nextResult.get()
        #expect(firstImageSnapshot.image !== nextImageSnapshot.image)
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
        let firstResult = try #require(firstResults.contentSnapshots[layer.replayID])
        let firstImageSnapshot = try firstResult.get()

        // When
        layer.frame = CGRect(x: 20, y: 15, width: 100, height: 40)
        let secondRoot = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let secondResults = await snapshotter.takeImageSnapshots(for: secondRoot, changeset: .init(), timeout: 1)

        // Then
        let secondResult = try #require(secondResults.contentSnapshots[layer.replayID])
        let secondImageSnapshot = try secondResult.get()
        #expect(firstImageSnapshot.image === secondImageSnapshot.image)
        #expect(secondImageSnapshot.frame == CGRect(x: 20, y: 15, width: 100, height: 40))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Refreshes snapshot metadata when cached image is reused")
    func refreshesSnapshotMetadataWhenCachedImageIsReused() async throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let layer = CATextLayer()
        layer.frame = CGRect(x: 10, y: 10, width: 100, height: 40)
        layer.backgroundColor = UIColor.red.cgColor
        layer.contentsScale = 1
        rootLayer.addSublayer(layer)

        let snapshotter = ImageSnapshotter()
        let firstRoot = try #require(
            CALayerSnapshot(
                from: rootLayer,
                in: .mockAny(textAndInputPrivacyLevel: .maskAll, imagePrivacyLevel: .maskNone)
            )
        )
        let firstResults = await snapshotter.takeImageSnapshots(for: firstRoot, changeset: .init(), timeout: 1)
        let firstResult = try #require(firstResults.contentSnapshots[layer.replayID])
        let firstImageSnapshot = try firstResult.get()

        // When
        let delegate = UIView()
        layer.delegate = delegate

        let secondRoot = try #require(
            CALayerSnapshot(
                from: rootLayer,
                in: .mockAny(textAndInputPrivacyLevel: .maskSensitiveInputs, imagePrivacyLevel: .maskAll)
            )
        )
        let secondResults = await snapshotter.takeImageSnapshots(for: secondRoot, changeset: .init(), timeout: 1)

        // Then
        let secondResult = try #require(secondResults.contentSnapshots[layer.replayID])
        let secondImageSnapshot = try secondResult.get()
        #expect(firstImageSnapshot.image === secondImageSnapshot.image)
        #expect(secondImageSnapshot.textAndInputPrivacyLevel == .maskSensitiveInputs)
        #expect(secondImageSnapshot.imagePrivacyLevel == .maskAll)
        #expect(secondImageSnapshot.layerClass == CATextLayer.self)
        #expect(secondImageSnapshot.delegateClass == UIView.self)
        #expect(secondImageSnapshot.hasLayerSemantics)
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
        let firstResult = try #require(firstResults.contentSnapshots[layer.replayID])
        let firstImageSnapshot = try firstResult.get()

        // When
        layer.backgroundColor = UIColor.blue.cgColor
        let secondRoot = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let changeset = CALayerChangeset.mockChange(for: layer, aspects: .display)
        let secondResults = await snapshotter.takeImageSnapshots(for: secondRoot, changeset: changeset, timeout: 1)

        // Then
        let secondResult = try #require(secondResults.contentSnapshots[layer.replayID])
        let secondImageSnapshot = try secondResult.get()
        #expect(firstImageSnapshot.image !== secondImageSnapshot.image)
        #expect(secondImageSnapshot.frame == layer.frame)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Invalidates cached image when occluded layer content changes")
    func invalidatesCachedImageWhenOccludedLayerContentChanges() async throws {
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
        let firstResult = try #require(firstResults.contentSnapshots[layer.replayID])
        let firstImageSnapshot = try firstResult.get()

        layer.backgroundColor = UIColor.blue.cgColor

        let occluder = CALayer()
        occluder.frame = rootLayer.bounds
        occluder.backgroundColor = UIColor.white.cgColor
        occluder.zPosition = 1
        rootLayer.addSublayer(occluder)

        let occludedRootSnapshot = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let occludedRoot = try #require(occludedRootSnapshot.removingOccluded())
        let changeset = CALayerChangeset.mockChange(for: layer, aspects: .display)

        // When
        let occludedResults = await snapshotter.takeImageSnapshots(for: occludedRoot, changeset: changeset, timeout: 1)

        // Then
        #expect(!occludedRoot.sublayers.contains { $0.layer.matches(layer) })
        #expect(occludedResults.contentSnapshots[layer.replayID] == nil)

        occluder.removeFromSuperlayer()

        let revealedRoot = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let revealedResults = await snapshotter.takeImageSnapshots(for: revealedRoot, changeset: .init(), timeout: 1)
        let revealedResult = try #require(revealedResults.contentSnapshots[layer.replayID])
        let revealedImageSnapshot = try revealedResult.get()
        #expect(firstImageSnapshot.image !== revealedImageSnapshot.image)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Invalidates cached image when occluded ignored sublayer changes")
    func invalidatesCachedImageWhenOccludedIgnoredSublayerChanges() async throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 10, y: 10, width: 100, height: 40)
        imageView.layer.contentsScale = 1
        rootLayer.addSublayer(imageView.layer)

        let ignoredSublayer = CALayer()
        ignoredSublayer.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        ignoredSublayer.backgroundColor = UIColor.red.cgColor
        imageView.layer.addSublayer(ignoredSublayer)

        let snapshotter = ImageSnapshotter()
        let firstRoot = try #require(
            CALayerSnapshot(from: rootLayer, in: .mockAny(imagePrivacyLevel: .maskNone))
        )
        let firstResults = await snapshotter.takeImageSnapshots(for: firstRoot, changeset: .init(), timeout: 1)
        let firstResult = try #require(firstResults.contentSnapshots[imageView.layer.replayID])
        let firstImageSnapshot = try firstResult.get()

        ignoredSublayer.backgroundColor = UIColor.blue.cgColor

        let occluder = CALayer()
        occluder.frame = rootLayer.bounds
        occluder.backgroundColor = UIColor.white.cgColor
        occluder.zPosition = 1
        rootLayer.addSublayer(occluder)

        let occludedRootSnapshot = try #require(
            CALayerSnapshot(from: rootLayer, in: .mockAny(imagePrivacyLevel: .maskNone))
        )
        let occludedRoot = try #require(occludedRootSnapshot.removingOccluded())
        let changeset = CALayerChangeset.mockChange(for: ignoredSublayer, aspects: .display)

        // When
        let occludedResults = await snapshotter.takeImageSnapshots(for: occludedRoot, changeset: changeset, timeout: 1)

        // Then
        #expect(!occludedRoot.sublayers.contains { $0.layer.matches(imageView.layer) })
        #expect(occludedResults.contentSnapshots[imageView.layer.replayID] == nil)

        occluder.removeFromSuperlayer()

        let revealedRoot = try #require(
            CALayerSnapshot(from: rootLayer, in: .mockAny(imagePrivacyLevel: .maskNone))
        )
        let revealedResults = await snapshotter.takeImageSnapshots(for: revealedRoot, changeset: .init(), timeout: 1)
        let revealedResult = try #require(revealedResults.contentSnapshots[imageView.layer.replayID])
        let revealedImageSnapshot = try revealedResult.get()
        #expect(firstImageSnapshot.image !== revealedImageSnapshot.image)
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
        let result = try #require(results.contentSnapshots[layer.replayID])
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
        let result = try #require(results.contentSnapshots[layer.replayID])
        let imageSnapshot = try result.get()
        #expect(imageSnapshot.frame == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(imageSnapshot.image.size == CGSize(width: 100, height: 100))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private struct MaskFixture {
        let rootLayer: CALayer
        let maskedLayer: CALayer
        let mask: CALayer
        let maskChild: CALayer

        init() {
            let rootLayer = CALayer()
            rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

            let maskedLayer = CALayer()
            maskedLayer.frame = CGRect(x: 10, y: 10, width: 100, height: 40)
            rootLayer.addSublayer(maskedLayer)

            let child = CATextLayer()
            child.frame = maskedLayer.bounds
            child.backgroundColor = UIColor.red.cgColor
            child.contentsScale = 1
            maskedLayer.addSublayer(child)

            let mask = CALayer()
            mask.bounds = maskedLayer.bounds
            let maskChild = CALayer()
            maskChild.frame = maskedLayer.bounds
            maskChild.backgroundColor = UIColor.black.cgColor
            mask.addSublayer(maskChild)
            maskedLayer.mask = mask

            self.init(
                rootLayer: rootLayer,
                maskedLayer: maskedLayer,
                mask: mask,
                maskChild: maskChild
            )
        }

        init(rootLayer: CALayer, maskedLayer: CALayer, mask: CALayer, maskChild: CALayer) {
            self.rootLayer = rootLayer
            self.maskedLayer = maskedLayer
            self.mask = mask
            self.maskChild = maskChild
        }
    }
}
#endif
