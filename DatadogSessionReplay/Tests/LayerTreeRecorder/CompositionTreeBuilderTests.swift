/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import Testing
import UIKit
import WebKit
import DatadogInternal

@_spi(Internal)
@testable import DatadogSessionReplay

@MainActor
struct CompositionTreeBuilderTests {
    private final class SafeAreaWebView: WKWebView {
        var stubbedSafeAreaInsets: UIEdgeInsets = .zero

        override var safeAreaInsets: UIEdgeInsets {
            stubbedSafeAreaInsets
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates visible webview wireframe")
    func buildCreatesVisibleWebViewWireframe() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let webView = WKWebView(frame: CGRect(x: 10, y: 20, width: 60, height: 40))
        webView.layer.backgroundColor = UIColor.red.cgColor
        webView.layer.borderColor = UIColor.green.cgColor
        webView.layer.borderWidth = 2
        webView.layer.cornerRadius = 6
        rootView.addSubview(webView)

        let root = try #require(CALayerSnapshot(from: rootView.layer, in: .mockAny()))
        let slotID = webView.hash

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [slotID],
            imageSnapshotResults: [:]
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.count == 1)
        #expect(output.compositionTree.root.children.first?.id == Int64(slotID))
        #expect(output.compositionTree.root.children.first?.type == .wireframe)
        #expect(hiddenWebViewSlotIDs(in: output.wireframes).isEmpty)

        #expect(output.wireframes.count == 1)
        guard case .webviewWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a webview wireframe")
            return
        }

        #expect(wireframe.id == Int64(slotID))
        #expect(wireframe.slotId == String(slotID))
        #expect(wireframe.isVisible == true)
        #expect(wireframe.x == 10)
        #expect(wireframe.y == 20)
        #expect(wireframe.width == 60)
        #expect(wireframe.height == 40)
        #expect(wireframe.border?.color == "#00FF00FF")
        #expect(wireframe.border?.width == 2)
        #expect(wireframe.shapeStyle?.backgroundColor == "#FF0000FF")
        #expect(wireframe.shapeStyle?.cornerRadius == 6)
        #expect(wireframe.shapeStyle?.opacity == nil)
        #expect(wireframe.clip == nil)
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build offsets webview wireframe for safe-area adjusted content")
    func buildOffsetsWebViewWireframeForSafeAreaAdjustedContent() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let webView = SafeAreaWebView(frame: CGRect(x: 10, y: 20, width: 60, height: 40))
        webView.stubbedSafeAreaInsets = UIEdgeInsets(top: 30, left: 0, bottom: 0, right: 0)
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        rootView.addSubview(webView)

        let root = try #require(CALayerSnapshot(from: rootView.layer, in: .mockAny()))
        let slotID = webView.hash

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [slotID],
            imageSnapshotResults: [:]
        )

        // When
        let output = builder.build()

        // Then
        guard case .webviewWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a webview wireframe")
            return
        }

        #expect(wireframe.x == 10)
        #expect(wireframe.y == 50)
        #expect(wireframe.width == 60)
        #expect(wireframe.height == 40)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates text wireframe for label")
    func buildCreatesTextWireframeForLabel() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let label = UILabel(frame: CGRect(x: 10, y: 20, width: 100, height: 30))
        label.text = "Hello, world!"
        label.textColor = .blue
        label.textAlignment = .right
        label.font = .systemFont(ofSize: 17)
        label.adjustsFontSizeToFitWidth = true
        label.lineBreakMode = .byTruncatingMiddle
        label.layer.backgroundColor = UIColor.red.cgColor
        label.layer.borderColor = UIColor.green.cgColor
        label.layer.borderWidth = 2
        label.layer.cornerRadius = 4
        rootView.addSubview(label)

        let root = try #require(CALayerSnapshot(
            from: rootView.layer,
            in: .mockAny(textAndInputPrivacyLevel: .maskSensitiveInputs)
        ))
        let labelSnapshot = try #require(root.sublayers.first)

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshotResults: [:]
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.count == 1)
        #expect(output.compositionTree.root.children.first?.id == labelSnapshot.replayID)
        #expect(output.compositionTree.root.children.first?.type == .wireframe)

        #expect(output.wireframes.count == 1)
        guard case .textWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a text wireframe")
            return
        }

        #expect(wireframe.id == labelSnapshot.replayID)
        #expect(wireframe.x == 10)
        #expect(wireframe.y == 20)
        #expect(wireframe.width == 100)
        #expect(wireframe.height == 30)
        #expect(wireframe.text == "Hello, world!")
        #expect(wireframe.textPosition?.alignment?.horizontal == .right)
        #expect(wireframe.textPosition?.alignment?.vertical == .center)
        #expect(wireframe.textPosition?.padding == nil)
        #expect(wireframe.textStyle.color == "#0000FFFF")
        #expect(wireframe.textStyle.size == 15)
        #expect(wireframe.textStyle.truncationMode == .middle)
        #expect(wireframe.border?.color == "#00FF00FF")
        #expect(wireframe.border?.width == 2)
        #expect(wireframe.shapeStyle?.backgroundColor == "#FF0000FF")
        #expect(wireframe.shapeStyle?.cornerRadius == 4)
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build masks label text for mask all privacy")
    func buildMasksLabelTextForMaskAllPrivacy() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let label = UILabel(frame: CGRect(x: 10, y: 20, width: 100, height: 30))
        label.text = "Hello world"
        rootView.addSubview(label)

        let root = try #require(CALayerSnapshot(
            from: rootView.layer,
            in: .mockAny(textAndInputPrivacyLevel: .maskAll)
        ))

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshotResults: [:]
        )

        // When
        let output = builder.build()

        // Then
        guard case .textWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a text wireframe")
            return
        }

        #expect(wireframe.text == "xxxxx xxxxx")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build skips empty label without appearance")
    func buildSkipsEmptyLabelWithoutAppearance() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let label = UILabel(frame: CGRect(x: 10, y: 20, width: 100, height: 30))
        rootView.addSubview(label)

        let root = try #require(CALayerSnapshot(from: rootView.layer, in: .mockAny()))

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshotResults: [:]
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.isEmpty)
        #expect(output.wireframes.isEmpty)
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates image wireframe for image snapshot")
    func buildCreatesImageWireframeForImageSnapshot() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let imageView = UIImageView(image: UIImage.mockWith(color: .red))
        imageView.frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        imageView.layer.backgroundColor = UIColor.blue.cgColor
        imageView.layer.borderColor = UIColor.green.cgColor
        imageView.layer.borderWidth = 2
        imageView.layer.cornerRadius = 4
        rootView.addSubview(imageView)

        let root = try #require(CALayerSnapshot(from: rootView.layer, in: .mockAny(imagePrivacyLevel: .maskNone)))
        let imageSnapshot = try #require(root.sublayers.first)
        let snapshotImage = UIImage.mockWith(color: .red)
        let renderedImage = ImageSnapshot.mockAny(
            image: snapshotImage,
            frame: imageSnapshot.absoluteFrame,
            layerClass: imageSnapshot.layerClass,
            delegateClass: imageSnapshot.delegateClass,
            hasLayerSemantics: false,
            imagePrivacyLevel: .maskNone
        )

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshotResults: [imageSnapshot.replayID: .success(renderedImage)]
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.count == 1)
        #expect(output.compositionTree.root.children.first?.id == imageSnapshot.replayID)
        #expect(output.compositionTree.root.children.first?.type == .wireframe)

        #expect(output.wireframes.count == 1)
        guard case .imageWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected an image wireframe")
            return
        }

        let resource = try #require(output.resources.first)
        #expect(output.resources.count == 1)
        #expect(resource.mimeType == "image/png")
        #expect(resource.calculateData().isEmpty == false)
        #expect(wireframe.id == imageSnapshot.replayID)
        #expect(wireframe.x == 10)
        #expect(wireframe.y == 20)
        #expect(wireframe.width == 100)
        #expect(wireframe.height == 40)
        #expect(wireframe.isEmpty == false)
        #expect(wireframe.mimeType == resource.mimeType)
        #expect(wireframe.resourceId == resource.calculateIdentifier())
        #expect(wireframe.border == nil)
        #expect(wireframe.shapeStyle == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates placeholder for image without snapshot result")
    func buildCreatesPlaceholderForImageWithoutSnapshotResult() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        rootView.addSubview(imageView)

        let root = try #require(
            CALayerSnapshot(from: rootView.layer, in: .mockAny(imagePrivacyLevel: .maskNonBundledOnly))
        )
        let imageSnapshot = try #require(root.sublayers.first)

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshotResults: [:]
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.wireframes.count == 1)
        guard case .placeholderWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a placeholder wireframe")
            return
        }

        #expect(wireframe.id == imageSnapshot.replayID)
        #expect(wireframe.label == "Content Image")
        #expect(wireframe.x == 10)
        #expect(wireframe.y == 20)
        #expect(wireframe.width == 100)
        #expect(wireframe.height == 40)
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates placeholder for timed out image snapshot")
    func buildCreatesPlaceholderForTimedOutImageSnapshot() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        rootView.addSubview(imageView)

        let root = try #require(CALayerSnapshot(from: rootView.layer, in: .mockAny(imagePrivacyLevel: .maskNone)))
        let imageSnapshot = try #require(root.sublayers.first)

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshotResults: [imageSnapshot.replayID: .failure(.timedOut)]
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.wireframes.count == 1)
        guard case .placeholderWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a placeholder wireframe")
            return
        }

        #expect(wireframe.id == imageSnapshot.replayID)
        #expect(wireframe.label == "Timed out")
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build skips discarded image snapshot")
    func buildSkipsDiscardedImageSnapshot() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let imageView = UIImageView(image: UIImage())
        imageView.frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        rootView.addSubview(imageView)

        let root = try #require(CALayerSnapshot(from: rootView.layer, in: .mockAny(imagePrivacyLevel: .maskNone)))
        let imageSnapshot = try #require(root.sublayers.first)

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshotResults: [imageSnapshot.replayID: .failure(.discarded)]
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.isEmpty)
        #expect(output.wireframes.isEmpty)
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build can be reused without accumulating output state")
    func buildCanBeReusedWithoutAccumulatingOutputState() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let containerLayer = CALayer()
        containerLayer.frame = CGRect(x: 40, y: 50, width: 60, height: 70)

        let leafLayer = CALayer()
        leafLayer.frame = CGRect(x: 1, y: 2, width: 30, height: 40)

        containerLayer.addSublayer(leafLayer)
        rootLayer.addSublayer(containerLayer)

        let root = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let container = try #require(root.sublayers.first)

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [42],
            imageSnapshotResults: [:]
        )

        // When
        let firstOutput = builder.build()
        let secondOutput = builder.build()

        // Then
        #expect(firstOutput.compositionTree.layers?.map(\.id) == [container.replayID])
        #expect(secondOutput.compositionTree.layers?.map(\.id) == [container.replayID])
        #expect(hiddenWebViewSlotIDs(in: firstOutput.wireframes) == ["42"])
        #expect(hiddenWebViewSlotIDs(in: secondOutput.wireframes) == ["42"])
        #expect(firstOutput.resources.isEmpty)
        #expect(secondOutput.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private func hiddenWebViewSlotIDs(in wireframes: [SRWireframe]) -> [String] {
        wireframes.compactMap { wireframe in
            guard case .webviewWireframe(let value) = wireframe, value.isVisible == false else {
                return nil
            }
            return value.slotId
        }
    }
}
#endif
