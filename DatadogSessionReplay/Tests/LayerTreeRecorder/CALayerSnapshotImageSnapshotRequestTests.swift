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
import WebKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct CALayerSnapshotImageSnapshotRequestTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips content snapshot request for visual effect")
    func skipsContentSnapshotRequestForVisualEffect() {
        // Given
        let snapshot = CALayerSnapshot.mockWith(
            observation: .init(semantics: .visualEffect(.glassGroup))
        )
        let cache = ImageSnapshotCache()
        cache.setContentSnapshotData(.mockAny(), forReplayID: snapshot.replayID)

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.compactMap(\.content).isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips content snapshot request for gradient")
    func skipsContentSnapshotRequestForGradient() throws {
        // Given
        let gradient = try #require(
            CALayerSnapshot.SemanticObservation.GradientSemantics(
                type: .axial,
                colors: [UIColor.red.cgColor, UIColor.blue.cgColor],
                locations: nil,
                startPoint: CGPoint(x: 0.5, y: 0),
                endPoint: CGPoint(x: 0.5, y: 1)
            )
        )
        let snapshot = CALayerSnapshot.mockWith(
            observation: .init(semantics: .gradient(gradient))
        )
        let cache = ImageSnapshotCache()
        cache.setContentSnapshotData(.mockAny(), forReplayID: snapshot.replayID)

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.compactMap(\.content).isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for plain layer with contents")
    func createsRequestForPlainLayerWithContents() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        layer.contents = NSObject()
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.replayID == snapshot.replayID)
        #expect(request.layer == snapshot.layer)
        #expect(request.geometry.renderBounds == snapshot.contentGeometry.renderBounds)
        #expect(request.geometry.localRect == snapshot.contentGeometry.localRect)
        #expect(request.geometry.frame == snapshot.contentGeometry.frame)
        #expect(request.hasChanges == false)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for plain layer with content changes")
    func createsRequestForPlainLayerWithContentChanges() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let changeset = CALayerChangeset.mockChange(for: layer, aspects: .display)
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: changeset, cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer == snapshot.layer)
        #expect(request.hasChanges)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for plain layer with cached snapshot data")
    func createsRequestForPlainLayerWithCachedSnapshotData() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))

        let imageSnapshot = ContentSnapshot.mockAny()
        let snapshotData = ContentSnapshotData.mockAny(snapshot: imageSnapshot)
        let cache = ImageSnapshotCache()
        cache.setContentSnapshotData(snapshotData, forReplayID: snapshot.replayID)

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer == snapshot.layer)
        #expect(request.previousSnapshotData?.snapshot === imageSnapshot)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates mask request for container with mask")
    func createsMaskRequestForContainerWithMask() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)

        let child = CATextLayer()
        child.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        layer.addSublayer(child)

        let mask = CALayer()
        mask.frame = CGRect(x: 4, y: 5, width: 20, height: 10)
        let maskChild = CALayer()
        maskChild.frame = layer.bounds
        maskChild.backgroundColor = UIColor.black.cgColor
        mask.addSublayer(maskChild)
        layer.mask = mask

        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        let request = try #require(requests.first { $0.mask != nil }?.mask)
        #expect(request.replayID == mask.replayID)
        #expect(request.layer.matches(mask))
        #expect(request.bounds == layer.bounds)
        #expect(request.frame == mask.frame)
        #expect(request.dependencies.contains { $0.matches(mask) })
        #expect(request.dependencies.contains { $0.matches(maskChild) })
        #expect(!request.hasChanges)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Marks mask request changed when mask dependency changes")
    func marksMaskRequestChangedWhenMaskDependencyChanges() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)

        let child = CATextLayer()
        child.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        layer.addSublayer(child)

        let mask = CALayer()
        let maskChild = CALayer()
        maskChild.frame = layer.bounds
        mask.addSublayer(maskChild)
        layer.mask = mask

        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let changeset = CALayerChangeset.mockChange(for: maskChild, aspects: .layout)
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: changeset, cache: cache)

        // Then
        let request = try #require(requests.first { $0.mask != nil }?.mask)
        #expect(request.layer.matches(mask))
        #expect(request.hasChanges)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates mask request for transparent container mask")
    func createsMaskRequestForTransparentContainerMask() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)

        let child = CATextLayer()
        child.frame = layer.bounds
        layer.addSublayer(child)

        let mask = CALayer()
        mask.bounds = layer.bounds
        mask.opacity = 0
        layer.mask = mask

        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        let request = try #require(requests.first { $0.mask != nil }?.mask)
        #expect(request.layer.matches(mask))
        #expect(request.dependencies.contains { $0.matches(mask) })
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips mask request for leaf layer")
    func skipsMaskRequestForLeafLayer() throws {
        // Given
        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)

        let mask = CALayer()
        mask.bounds = layer.bounds
        layer.mask = mask

        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(!requests.contains { $0.mask != nil })
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips plain layer without contents, content changes, or cache")
    func skipsPlainLayerWithoutContentsChangesOrCachedSnapshotData() throws {
        // Given
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for layer subclass without contents")
    func createsRequestForLayerSubclassWithoutContents() throws {
        // Given
        let layer = CATextLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        let snapshot = try #require(CALayerSnapshot(from: layer, in: .mockAny()))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.replayID == snapshot.replayID)
        #expect(request.layerClass == CATextLayer.self)
        #expect(request.delegateClass == nil)
        #expect(request.hasLayerSemantics)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for semantic image layer when image privacy masks none")
    func createsRequestForSemanticImageLayerWhenImagePrivacyMasksNone() throws {
        // Given
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        imageView.layer.contents = NSObject()

        let child = CATextLayer()
        child.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        imageView.layer.addSublayer(child)

        let snapshot = try #require(CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNone)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.replayID == snapshot.replayID)
        #expect(request.layer.matches(imageView.layer))
        #expect(request.hasContents)
        #expect(!request.hasLayerSemantics)
        #expect(!requests.contains { $0.content?.layer.matches(child) == true })
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips empty semantic image layer")
    func skipsEmptySemanticImageLayer() throws {
        // Given
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        imageView.layer.contents = NSObject()

        let snapshot = try #require(CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNone)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for semantic image layer with dependencies")
    func createsRequestForSemanticImageLayerWithDependencies() throws {
        // Given
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))

        let dependency = CALayer()
        dependency.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        dependency.contents = NSObject()
        imageView.layer.addSublayer(dependency)

        let snapshot = try #require(CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNone)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer.matches(imageView.layer))
        #expect(!request.hasContents)
        #expect(request.dependencies.contains { $0.matches(dependency) })
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips semantic image layer when image privacy masks all")
    func skipsSemanticImageLayerWhenImagePrivacyMasksAll() throws {
        // Given
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        imageView.layer.contents = NSObject()

        let snapshot = try #require(CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskAll)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for progress view image sublayer when image privacy masks all")
    func createsRequestForProgressViewImageSublayerWhenImagePrivacyMasksAll() throws {
        // Given
        let progressView = UIProgressView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        imageView.layer.contents = NSObject()
        progressView.addSubview(imageView)

        let snapshot = try #require(CALayerSnapshot(from: progressView.layer, in: .mockAny(imagePrivacyLevel: .maskAll)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer.matches(imageView.layer))
        #expect(request.imagePrivacyLevel == .maskNone)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for slider image sublayer when image privacy masks all")
    func createsRequestForSliderImageSublayerWhenImagePrivacyMasksAll() throws {
        // Given
        let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        imageView.layer.contents = NSObject()
        slider.addSubview(imageView)

        let snapshot = try #require(CALayerSnapshot(from: slider.layer, in: .mockAny(imagePrivacyLevel: .maskAll)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer.matches(imageView.layer))
        #expect(request.imagePrivacyLevel == .maskNone)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for button image sublayer when image privacy masks all")
    func createsRequestForButtonImageSublayerWhenImagePrivacyMasksAll() throws {
        // Given
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        imageView.layer.contents = NSObject()
        button.addSubview(imageView)

        let snapshot = try #require(CALayerSnapshot(from: button.layer, in: .mockAny(imagePrivacyLevel: .maskAll)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer.matches(imageView.layer))
        #expect(request.imagePrivacyLevel == .maskNone)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips button image sublayer when button image privacy override masks all")
    func skipsButtonImageSublayerWhenButtonImagePrivacyOverrideMasksAll() throws {
        // Given
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        button.dd.sessionReplayPrivacyOverrides.imagePrivacy = .maskAll

        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        imageView.layer.contents = NSObject()
        button.addSubview(imageView)

        let snapshot = try #require(CALayerSnapshot(from: button.layer, in: .mockAny(imagePrivacyLevel: .maskNone)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips semantic image layer when image privacy masks non-bundled images")
    func skipsSemanticImageLayerWhenImagePrivacyMasksNonBundledImages() throws {
        // Given
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        imageView.layer.contents = NSObject()

        let snapshot = try #require(CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNonBundledOnly)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for highlighted semantic image layer when highlighted image is bundled")
    func createsRequestForHighlightedSemanticImageLayerWhenHighlightedImageIsBundled() throws {
        // Given
        let imageView = UIImageView(image: UIImage(), highlightedImage: BundledImageMock())
        imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        imageView.isHighlighted = true
        imageView.layer.contents = NSObject()

        let snapshot = try #require(CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNonBundledOnly)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer.matches(imageView.layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for highlighted semantic image layer when fallback image is bundled")
    func createsRequestForHighlightedSemanticImageLayerWhenFallbackImageIsBundled() throws {
        // Given
        let imageView = UIImageView(image: BundledImageMock())
        imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        imageView.isHighlighted = true
        imageView.layer.contents = NSObject()

        let snapshot = try #require(CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNonBundledOnly)))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer.matches(imageView.layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for semantic image layer when ignored sublayer changes")
    func createsRequestForSemanticImageLayerWhenIgnoredSublayerChanges() throws {
        // Given
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        imageView.layer.contents = NSObject()

        let ignoredSublayer = CALayer()
        ignoredSublayer.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        imageView.layer.addSublayer(ignoredSublayer)

        let snapshot = try #require(
            CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNone))
        )
        let changeset = CALayerChangeset.mockChange(for: ignoredSublayer, aspects: .display)
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: changeset, cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(snapshot.sublayers.isEmpty)
        #expect(snapshot.dependencies.contains { $0.matches(ignoredSublayer) })
        #expect(request.layer.matches(imageView.layer))
        #expect(request.dependencies.contains { $0.matches(ignoredSublayer) })
        #expect(request.hasChanges)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for semantic image layer when ignored sublayer lays out")
    func createsRequestForSemanticImageLayerWhenIgnoredSublayerLaysOut() throws {
        // Given
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        imageView.layer.contents = NSObject()

        let ignoredSublayer = CALayer()
        ignoredSublayer.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        imageView.layer.addSublayer(ignoredSublayer)

        let snapshot = try #require(CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNone)))
        let changeset = CALayerChangeset.mockChange(for: ignoredSublayer, aspects: .layout)
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: changeset, cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer.matches(imageView.layer))
        #expect(request.hasChanges)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for semantic image layer when ignored sublayer is replaced")
    func createsRequestForSemanticImageLayerWhenIgnoredSublayerIsReplaced() throws {
        // Given
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        imageView.layer.contents = NSObject()

        let previousIgnoredSublayer = CALayer()
        previousIgnoredSublayer.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        imageView.layer.addSublayer(previousIgnoredSublayer)
        let previousSnapshot = try #require(
            CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNone))
        )

        previousIgnoredSublayer.removeFromSuperlayer()
        let currentIgnoredSublayer = CALayer()
        currentIgnoredSublayer.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        imageView.layer.addSublayer(currentIgnoredSublayer)

        let snapshot = try #require(
            CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNone))
        )
        let cache = ImageSnapshotCache()
        cache.setContentSnapshotData(
            .mockAny(dependencies: previousSnapshot.dependencies),
            forReplayID: snapshot.replayID
        )
        let changeset = CALayerChangeset.mockChange(for: imageView.layer, aspects: .layout)

        // When
        let requests = snapshot.imageSnapshotRequests(for: changeset, cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer.matches(imageView.layer))
        #expect(request.dependencies.contains { $0.matches(currentIgnoredSublayer) })
        #expect(request.hasChanges)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not mark semantic image layer changed when owner only lays out")
    func doesNotMarkSemanticImageLayerChangedWhenOwnerOnlyLaysOut() throws {
        // Given
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        imageView.layer.contents = NSObject()

        let snapshot = try #require(
            CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNone))
        )
        let cache = ImageSnapshotCache()
        cache.setContentSnapshotData(
            .mockAny(dependencies: snapshot.dependencies),
            forReplayID: snapshot.replayID
        )
        let changeset = CALayerChangeset.mockChange(for: imageView.layer, aspects: .layout)

        // When
        let requests = snapshot.imageSnapshotRequests(for: changeset, cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer.matches(imageView.layer))
        #expect(!request.hasChanges)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips web view layer")
    func skipsWebViewLayer() throws {
        // Given
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        webView.layer.contents = NSObject()
        let snapshot = try #require(CALayerSnapshot(from: webView.layer, in: .mockAny()))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Skips private layer")
    func skipsPrivateLayer() throws {
        // Given
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        view.dd.sessionReplayPrivacyOverrides.hide = true
        view.layer.contents = NSObject()
        let snapshot = try #require(CALayerSnapshot(from: view.layer, in: .mockAny()))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates request for visible child of zero-sized non-clipping container")
    func createsRequestForVisibleChildOfZeroSizedNonClippingContainer() throws {
        // Given
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        imageView.layer.contents = NSObject()

        let child = try #require(
            CALayerSnapshot(from: imageView.layer, in: .mockAny(imagePrivacyLevel: .maskNone))
        )
        let container = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: .zero,
            sublayers: [child]
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [container])
        let cache = ImageSnapshotCache()

        // When
        let requests = root.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        #expect(requests.first?.content?.layer.matches(imageView.layer) == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Keeps traversing image-capable container")
    func keepsTraversingImageCapableContainer() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let parent = CALayer()
        parent.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        parent.contents = NSObject()
        root.addSublayer(parent)

        let child = CATextLayer()
        child.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        parent.addSublayer(child)

        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.count == 1)
        let request = try #require(requests.first?.content)
        #expect(request.layer.matches(child))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Keeps traversing when container image would include web view")
    func keepsTraversingWhenContainerImageWouldIncludeWebView() throws {
        // Given
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        let parent = CALayer()
        parent.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        parent.contents = NSObject()
        root.addSublayer(parent)

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        parent.addSublayer(webView.layer)

        let child = CATextLayer()
        child.frame = CGRect(x: 50, y: 50, width: 20, height: 20)
        parent.addSublayer(child)

        let snapshot = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let cache = ImageSnapshotCache()

        // When
        let requests = snapshot.imageSnapshotRequests(for: .init(), cache: cache)

        // Then
        #expect(requests.contains { $0.content?.layer.matches(child) == true })
        #expect(!requests.contains { $0.content?.layer.matches(parent) == true })
        #expect(!requests.contains { $0.content?.layer.matches(webView.layer) == true })
    }

    private final class BundledImageMock: UIImage, @unchecked Sendable {
        override var description: String {
            "named(mock-bundled-image)"
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension ImageSnapshotRequest {
    var content: ContentSnapshotRequest? {
        guard case .content(let request) = self else {
            return nil
        }

        return request
    }

    var mask: MaskSnapshotRequest? {
        guard case .mask(let request) = self else {
            return nil
        }

        return request
    }
}

#endif
