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
            imageSnapshots: .init()
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
            imageSnapshots: .init()
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
            imageSnapshots: .init()
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
            imageSnapshots: .init()
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
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.isEmpty)
        #expect(output.wireframes.isEmpty)
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates shape wireframe for layer appearance")
    func buildCreatesShapeWireframeForLayerAppearance() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let layer = CALayer()
        layer.frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        layer.backgroundColor = UIColor.red.cgColor
        layer.borderColor = UIColor.green.cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 4
        rootLayer.addSublayer(layer)

        let root = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let layerSnapshot = try #require(root.sublayers.first)

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.count == 1)
        #expect(output.compositionTree.root.children.first?.id == layerSnapshot.replayID)
        #expect(output.compositionTree.root.children.first?.type == .wireframe)

        #expect(output.wireframes.count == 1)
        guard case .shapeWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(wireframe.id == layerSnapshot.replayID)
        #expect(wireframe.x == 10)
        #expect(wireframe.y == 20)
        #expect(wireframe.width == 100)
        #expect(wireframe.height == 40)
        #expect(wireframe.border?.color == "#00FF00FF")
        #expect(wireframe.border?.width == 2)
        #expect(wireframe.shapeStyle?.backgroundColor == "#FF0000FF")
        #expect(wireframe.shapeStyle?.cornerRadius == 4)
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build preserves positive subpoint dimensions")
    func buildPreservesPositiveSubpointDimensions() throws {
        // Given
        let frame = CGRect(x: 10, y: 20, width: 100, height: CGFloat(1) / 3)
        let contentSnapshot = CALayerSnapshot.mockWith(
            replayID: 3,
            absoluteFrame: frame,
            backgroundColor: UIColor.white.cgColor
        )
        let containerSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: frame,
            sublayers: [contentSnapshot]
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [containerSnapshot])
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        let layers = try #require(output.compositionTree.layers)
        let compositionLayer = try #require(layers.first)
        guard case .shapeWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(compositionLayer.height == 1)
        #expect(wireframe.height == 1)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates shape wireframe for linear gradient")
    func buildCreatesShapeWireframeForLinearGradient() throws {
        // Given
        let gradient = try #require(
            CALayerSnapshot.SemanticObservation.GradientSemantics(
                type: .axial,
                colors: [
                    UIColor.red.cgColor,
                    UIColor.green.cgColor,
                    UIColor.blue.cgColor
                ],
                locations: nil,
                startPoint: CGPoint(x: 0, y: 0.5),
                endPoint: CGPoint(x: 1, y: 0.5)
            )
        )
        let gradientSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            observation: .init(semantics: .gradient(gradient))
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [gradientSnapshot])
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children == [
            .init(id: gradientSnapshot.replayID, type: .wireframe)
        ])
        #expect(output.wireframes.count == 1)

        guard case .shapeWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a shape wireframe")
            return
        }
        let backgroundGradient = try #require(wireframe.shapeStyle?.backgroundGradient)
        guard case .linear(let gradient) = backgroundGradient else {
            Issue.record("Expected a linear gradient")
            return
        }

        #expect(wireframe.id == gradientSnapshot.replayID)
        #expect(wireframe.shapeStyle?.backgroundColor == nil)
        #expect(gradient.startPoint == .init(x: 0, y: 0.5))
        #expect(gradient.endPoint == .init(x: 1, y: 0.5))
        #expect(gradient.stops == [
            .init(color: "#FF0000FF", position: 0),
            .init(color: "#00FF00FF", position: 0.5),
            .init(color: "#0000FFFF", position: 1)
        ])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates gradient background wireframe for container")
    func buildCreatesGradientBackgroundWireframeForContainer() throws {
        // Given
        let gradient = try #require(
            CALayerSnapshot.SemanticObservation.GradientSemantics(
                type: .axial,
                colors: [UIColor.white.cgColor, UIColor.black.cgColor],
                locations: nil,
                startPoint: CGPoint(x: 0.5, y: 0),
                endPoint: CGPoint(x: 0.5, y: 1)
            )
        )
        let contentSnapshot = CALayerSnapshot.mockWith(
            replayID: 3,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            backgroundColor: UIColor.red.cgColor
        )
        let gradientSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            observation: .init(semantics: .gradient(gradient)),
            sublayers: [contentSnapshot]
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [gradientSnapshot])
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        let compositionLayer = try #require(
            output.compositionTree.layers?.first { $0.id == gradientSnapshot.replayID }
        )
        #expect(compositionLayer.children.contains {
            $0.id == gradientSnapshot.replayID && $0.type == .wireframe
        })
        #expect(output.wireframes.contains { wireframe in
            guard case .shapeWireframe(let shapeWireframe) = wireframe else {
                return false
            }
            return shapeWireframe.id == gradientSnapshot.replayID
        })
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build uses capsule corner radius for layer appearance inside liquid lens")
    func buildUsesCapsuleCornerRadiusForLayerAppearanceInsideLiquidLens() throws {
        // Given
        let contentSnapshot = CALayerSnapshot.mockWith(
            replayID: 3,
            absoluteFrame: CGRect(x: 10, y: 20, width: 37, height: 24),
            backgroundColor: UIColor.white.cgColor
        )
        let liquidLensSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 37, height: 24),
            observation: .init(semantics: .visualEffect(.liquidLens)),
            sublayers: [contentSnapshot]
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [liquidLensSnapshot])

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        let shapeWireframes = output.wireframes
            .compactMap { wireframe -> SRShapeWireframe? in
                guard case .shapeWireframe(let shapeWireframe) = wireframe else {
                    return nil
                }
                return shapeWireframe
            }
        let wireframe = try #require(
            shapeWireframes.first { $0.id == contentSnapshot.replayID }
        )

        #expect(wireframe.shapeStyle?.cornerRadius == 12)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates system background wireframe for glass group")
    func buildCreatesSystemBackgroundWireframeForGlassGroup() throws {
        // Given
        let visualEffectSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            observation: .init(semantics: .visualEffect(.glassGroup))
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [visualEffectSnapshot])
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        guard case .shapeWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(output.wireframes.count == 1)
        #expect(wireframe.id == visualEffectSnapshot.replayID)
        #expect(wireframe.shapeStyle?.backgroundColor == hexString(from: UIColor.systemBackground.cgColor))
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates system background wireframe for backdrop")
    func buildCreatesSystemBackgroundWireframeForBackdrop() throws {
        // Given
        let visualEffectSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            observation: .init(semantics: .visualEffect(.backdrop))
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [visualEffectSnapshot])
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        guard case .shapeWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(output.wireframes.count == 1)
        #expect(wireframe.id == visualEffectSnapshot.replayID)
        #expect(wireframe.shapeStyle?.backgroundColor == hexString(from: UIColor.systemBackground.cgColor))
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates shape wireframe using visual effect background color")
    func buildCreatesShapeWireframeUsingVisualEffectBackgroundColor() throws {
        // Given
        let visualEffectSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            observation: .init(semantics: .visualEffect(.background(.red)))
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [visualEffectSnapshot])
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        guard case .shapeWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(output.wireframes.count == 1)
        #expect(wireframe.id == visualEffectSnapshot.replayID)
        #expect(wireframe.shapeStyle?.backgroundColor == "#FF0000FF")
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build uses fallback color for visual effect background without color")
    func buildUsesFallbackColorForVisualEffectBackgroundWithoutColor() throws {
        // Given
        let visualEffectSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            observation: .init(semantics: .visualEffect(.background(nil)))
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [visualEffectSnapshot])
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        guard case .shapeWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(output.wireframes.count == 1)
        #expect(wireframe.id == visualEffectSnapshot.replayID)
        #expect(
            wireframe.shapeStyle?.backgroundColor == hexString(from: UIColor.secondarySystemFill.cgColor)
        )
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates hidden placeholder for private layer")
    func buildCreatesHiddenPlaceholderForPrivateLayer() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let privateView = UIView(frame: CGRect(x: 10, y: 20, width: 100, height: 40))
        privateView.dd.sessionReplayPrivacyOverrides.hide = true
        rootView.addSubview(privateView)

        let root = try #require(CALayerSnapshot(from: rootView.layer, in: .mockAny()))
        let privateSnapshot = try #require(root.sublayers.first)

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.count == 1)
        #expect(output.compositionTree.root.children.first?.id == privateSnapshot.replayID)
        #expect(output.compositionTree.root.children.first?.type == .wireframe)

        #expect(output.wireframes.count == 1)
        guard case .placeholderWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a placeholder wireframe")
            return
        }

        #expect(wireframe.id == privateSnapshot.replayID)
        #expect(wireframe.label == "Hidden")
        #expect(wireframe.x == 10)
        #expect(wireframe.y == 20)
        #expect(wireframe.width == 100)
        #expect(wireframe.height == 40)
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates mask image resource for container mask snapshot")
    func buildCreatesMaskImageResourceForContainerMaskSnapshot() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let containerLayer = CALayer()
        containerLayer.frame = CGRect(x: 10, y: 20, width: 100, height: 40)

        let leafLayer = CALayer()
        leafLayer.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        leafLayer.backgroundColor = UIColor.red.cgColor
        containerLayer.addSublayer(leafLayer)

        let maskLayer = CALayer()
        maskLayer.bounds = containerLayer.bounds
        maskLayer.backgroundColor = UIColor.black.cgColor
        containerLayer.mask = maskLayer

        rootLayer.addSublayer(containerLayer)

        let root = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let containerSnapshot = try #require(root.sublayers.first)
        let mask = try #require(containerSnapshot.mask)
        let maskSnapshot = MaskSnapshot.mockAny(image: UIImage.mockWith(color: .black))

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init(maskSnapshots: [mask.replayID: .success(maskSnapshot)])
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.count == 1)
        #expect(output.compositionTree.root.children.first?.id == containerSnapshot.replayID)
        #expect(output.compositionTree.root.children.first?.type == .layer)

        let container = try #require(output.compositionTree.layers?.first { $0.id == containerSnapshot.replayID })
        let modifier = try #require(container.modifiers?.first)
        let resource = try #require(output.resources.first)

        guard case .compositionLayerMaskImageModifier(let maskImageModifier) = modifier else {
            Issue.record("Expected a mask image modifier")
            return
        }

        #expect(output.resources.count == 1)
        #expect(maskImageModifier.resourceId == resource.calculateIdentifier())
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates shape wireframe for text input appearance")
    func buildCreatesShapeWireframeForTextInputAppearance() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let textView = UITextView(frame: CGRect(x: 10, y: 20, width: 100, height: 40))
        textView.backgroundColor = .red
        textView.layer.borderColor = UIColor.green.cgColor
        textView.layer.borderWidth = 2

        let contentLayer = CALayer()
        contentLayer.frame = CGRect(x: 5, y: 6, width: 20, height: 10)
        contentLayer.backgroundColor = UIColor.blue.cgColor
        textView.layer.addSublayer(contentLayer)

        rootView.addSubview(textView)

        let root = try #require(CALayerSnapshot(from: rootView.layer, in: .mockAny()))
        let textInputSnapshot = try #require(root.sublayers.first)

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.count == 1)
        #expect(output.compositionTree.root.children.first?.id == textInputSnapshot.replayID)
        #expect(output.compositionTree.root.children.first?.type == .layer)

        let textInputLayer = try #require(output.compositionTree.layers?.first { $0.id == textInputSnapshot.replayID })
        #expect(textInputLayer.children.contains {
            $0.id == textInputSnapshot.replayID && $0.type == .wireframe
        })

        let shapeWireframes = output.wireframes.compactMap { wireframe -> SRShapeWireframe? in
            guard case .shapeWireframe(let shapeWireframe) = wireframe else {
                return nil
            }
            return shapeWireframe
        }
        let wireframe = try #require(shapeWireframes.first {
            $0.id == textInputSnapshot.replayID
        })

        #expect(wireframe.x == 10)
        #expect(wireframe.y == 20)
        #expect(wireframe.width == 100)
        #expect(wireframe.height == 40)
        #expect(wireframe.border?.color == "#00FF00FF")
        #expect(wireframe.border?.width == 2)
        #expect(wireframe.shapeStyle?.backgroundColor == "#FF0000FF")
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
        let renderedImage = ContentSnapshot.mockAny(
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
            imageSnapshots: .init(contentSnapshots: [imageSnapshot.replayID: .success(renderedImage)])
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
    @Test("Build creates image wireframe for control snapshot")
    func buildCreatesImageWireframeForControlSnapshot() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let activityIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 20, width: 40, height: 40))
        activityIndicator.startAnimating()
        rootView.addSubview(activityIndicator)

        let root = try #require(CALayerSnapshot(
            from: rootView.layer,
            in: .mockAny(textAndInputPrivacyLevel: .maskAll, imagePrivacyLevel: .maskAll)
        ))
        let controlSnapshot = try #require(root.sublayers.first)
        let renderedImage = ContentSnapshot.mockAny(
            image: UIImage.mockWith(color: .red),
            frame: controlSnapshot.absoluteFrame,
            layerClass: controlSnapshot.layerClass,
            delegateClass: controlSnapshot.delegateClass,
            hasLayerSemantics: false,
            textAndInputPrivacyLevel: .maskAll,
            imagePrivacyLevel: .maskAll
        )

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init(contentSnapshots: [controlSnapshot.replayID: .success(renderedImage)])
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.count == 1)
        #expect(output.compositionTree.root.children.first?.id == controlSnapshot.replayID)
        #expect(output.compositionTree.root.children.first?.type == .wireframe)

        #expect(output.wireframes.count == 1)
        guard case .imageWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected an image wireframe")
            return
        }

        #expect(output.resources.count == 1)
        #expect(wireframe.id == controlSnapshot.replayID)
        #expect(wireframe.x == 10)
        #expect(wireframe.y == 20)
        #expect(wireframe.width == 40)
        #expect(wireframe.height == 40)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates shape wireframe when image snapshot redacts to placeholder")
    func buildCreatesShapeWireframeWhenImageSnapshotRedactsToPlaceholder() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let layer = CALayer()
        layer.frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        rootLayer.addSublayer(layer)

        let root = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let layerSnapshot = try #require(root.sublayers.first)
        let renderedImage = ContentSnapshot.mockAny(
            image: UIImage.mockWith(color: .red),
            frame: layerSnapshot.absoluteFrame,
            layerClass: try imageLayerClass(),
            delegateClass: layerSnapshot.delegateClass,
            hasLayerSemantics: true,
            imagePrivacyLevel: .maskAll
        )

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init(contentSnapshots: [layerSnapshot.replayID: .success(renderedImage)])
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.count == 1)
        #expect(output.compositionTree.root.children.first?.id == layerSnapshot.replayID)
        #expect(output.compositionTree.root.children.first?.type == .wireframe)

        #expect(output.wireframes.count == 1)
        guard case .shapeWireframe(let wireframe) = try #require(output.wireframes.first) else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(wireframe.id == layerSnapshot.replayID)
        #expect(wireframe.shapeStyle?.backgroundColor == "#FF0000FF")
        #expect(output.resources.isEmpty)
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
            imageSnapshots: .init()
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
    @Test("Build skips empty image view without appearance")
    func buildSkipsEmptyImageViewWithoutAppearance() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let imageView = UIImageView(frame: CGRect(x: 10, y: 20, width: 100, height: 40))
        rootView.addSubview(imageView)

        let root = try #require(CALayerSnapshot(from: rootView.layer, in: .mockAny(imagePrivacyLevel: .maskAll)))

        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children.isEmpty)
        #expect(output.wireframes.isEmpty)
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
            imageSnapshots: .init(contentSnapshots: [imageSnapshot.replayID: .failure(.timedOut)])
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
            imageSnapshots: .init(contentSnapshots: [imageSnapshot.replayID: .failure(.discarded)])
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
            imageSnapshots: .init()
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

private func imageLayerClass() throws -> AnyClass {
    try #require(NSClassFromString("SwiftUI.ImageLayer"))
}
#endif
