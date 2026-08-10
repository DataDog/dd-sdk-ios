/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import QuartzCore
import Testing
import UIKit

@_spi(Internal)
@testable import DatadogSessionReplay

@MainActor
struct LayerWireframeBuilderTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates shape wireframe for layer appearance")
    func buildCreatesShapeWireframeForLayerAppearance() throws {
        // Given
        let snapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            backgroundColor: UIColor.red.cgColor,
            cornerRadii: .init(
                cornerRadius: 4,
                maskedCorners: [
                    .layerMinXMinYCorner,
                    .layerMaxXMinYCorner,
                    .layerMinXMaxYCorner,
                    .layerMaxXMaxYCorner
                ]
            )
        )
        var builder = LayerWireframeBuilder(contentSnapshots: [:], webViewSlotIDs: [])

        // When
        let result = builder.build(
            from: snapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let output = try #require(result)

        // Then
        guard case .shapeWireframe(let wireframe) = output.wireframe else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(wireframe.id == Int64(namespace: .shape, replayID: snapshot.replayID))
        #expect(wireframe.shapeStyle?.backgroundColor == "#FF0000FF")
        #expect(wireframe.shapeStyle?.cornerRadius == 4)
        #expect(output.resource == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates text wireframe for label")
    func buildCreatesTextWireframeForLabel() throws {
        // Given
        let label = CALayerSnapshot.SemanticObservation.LabelSemantics(
            text: "Hello, world!",
            textColor: .blue,
            textAlignment: .right,
            font: .systemFont(ofSize: 17),
            adjustsFontSizeToFitWidth: false,
            lineBreakMode: .byTruncatingMiddle
        )
        let snapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 30),
            observation: .init(semantics: .label(label)),
            backgroundColor: UIColor.red.cgColor
        )
        var builder = LayerWireframeBuilder(contentSnapshots: [:], webViewSlotIDs: [])

        // When
        let result = builder.build(
            from: snapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let output = try #require(result)

        // Then
        guard case .textWireframe(let wireframe) = output.wireframe else {
            Issue.record("Expected a text wireframe")
            return
        }

        #expect(wireframe.text == "Hello, world!")
        #expect(wireframe.textPosition?.alignment?.horizontal == .right)
        #expect(wireframe.textStyle.color == "#0000FFFF")
        #expect(wireframe.textStyle.size == 17)
        #expect(wireframe.textStyle.truncationMode == .middle)
        #expect(wireframe.shapeStyle?.backgroundColor == "#FF0000FF")
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
        let snapshot = try #require(root.sublayers.first)
        var builder = LayerWireframeBuilder(contentSnapshots: [:], webViewSlotIDs: [])

        // When
        let result = builder.build(
            from: snapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let output = try #require(result)

        // Then
        guard case .textWireframe(let wireframe) = output.wireframe else {
            Issue.record("Expected a text wireframe")
            return
        }

        #expect(wireframe.text == "xxxxx xxxxx")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build skips empty label without appearance")
    func buildSkipsEmptyLabelWithoutAppearance() {
        // Given
        let label = CALayerSnapshot.SemanticObservation.LabelSemantics(
            text: nil,
            textColor: nil,
            textAlignment: .natural,
            font: nil,
            adjustsFontSizeToFitWidth: false,
            lineBreakMode: .byTruncatingTail
        )
        let snapshot = CALayerSnapshot.mockWith(
            observation: .init(semantics: .label(label))
        )
        var builder = LayerWireframeBuilder(contentSnapshots: [:], webViewSlotIDs: [])

        // When
        let output = builder.build(from: snapshot, textInput: nil, cornerRadius: nil)

        // Then
        #expect(output == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates shape wireframe for linear gradient")
    func buildCreatesShapeWireframeForLinearGradient() throws {
        // Given
        let gradient = try #require(
            CALayerSnapshot.SemanticObservation.GradientSemantics(
                type: .axial,
                colors: [UIColor.red.cgColor, UIColor.green.cgColor, UIColor.blue.cgColor],
                locations: nil,
                startPoint: CGPoint(x: 0, y: 0.5),
                endPoint: CGPoint(x: 1, y: 0.5)
            )
        )
        let snapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            observation: .init(semantics: .gradient(gradient))
        )
        var builder = LayerWireframeBuilder(contentSnapshots: [:], webViewSlotIDs: [])

        // When
        let result = builder.build(
            from: snapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let output = try #require(result)

        // Then
        guard case .shapeWireframe(let wireframe) = output.wireframe,
              case .linear(let gradient) = wireframe.shapeStyle?.backgroundGradient else {
            Issue.record("Expected a linear gradient shape wireframe")
            return
        }

        #expect(gradient.startPoint == .init(x: 0, y: 0.5))
        #expect(gradient.endPoint == .init(x: 1, y: 0.5))
        #expect(gradient.stops == [
            .init(color: "#FF0000FF", position: 0),
            .init(color: "#00FF00FF", position: 0.5),
            .init(color: "#0000FFFF", position: 1)
        ])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates visual effect fallbacks")
    func buildCreatesVisualEffectFallbacks() throws {
        // Given
        let frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        let corners = CALayerSnapshot.CornerRadii(
            cornerRadius: 12,
            maskedCorners: [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
        )
        let glassGroup = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: frame,
            observation: .init(semantics: .visualEffect(.glassGroup)),
            cornerRadii: corners
        )
        let glassGroupWithoutCorners = CALayerSnapshot.mockWith(
            replayID: 3,
            absoluteFrame: frame,
            observation: .init(semantics: .visualEffect(.glassGroup))
        )
        let backdrop = CALayerSnapshot.mockWith(
            replayID: 4,
            absoluteFrame: frame,
            observation: .init(semantics: .visualEffect(.backdrop))
        )
        let background = CALayerSnapshot.mockWith(
            replayID: 5,
            absoluteFrame: frame,
            observation: .init(semantics: .visualEffect(.background(.red)))
        )
        let backgroundWithoutColor = CALayerSnapshot.mockWith(
            replayID: 6,
            absoluteFrame: frame,
            observation: .init(semantics: .visualEffect(.background(nil)))
        )
        var builder = LayerWireframeBuilder(contentSnapshots: [:], webViewSlotIDs: [])

        // When
        let glassGroupOutput = builder.build(from: glassGroup, textInput: nil, cornerRadius: nil)
        let emptyGlassGroupOutput = builder.build(
            from: glassGroupWithoutCorners,
            textInput: nil,
            cornerRadius: nil
        )
        let backdropOutput = builder.build(from: backdrop, textInput: nil, cornerRadius: nil)
        let backgroundOutput = builder.build(from: background, textInput: nil, cornerRadius: nil)
        let fallbackOutput = builder.build(
            from: backgroundWithoutColor,
            textInput: nil,
            cornerRadius: nil
        )

        // Then
        #expect(try backgroundColor(in: glassGroupOutput) == hexString(from: UIColor.systemBackground.cgColor))
        #expect(try cornerRadius(in: glassGroupOutput) == 12)
        #expect(emptyGlassGroupOutput == nil)
        #expect(try backgroundColor(in: backdropOutput) == hexString(from: UIColor.systemBackground.cgColor))
        #expect(try backgroundColor(in: backgroundOutput) == "#FF0000FF")
        #expect(
            try backgroundColor(in: fallbackOutput) == hexString(from: UIColor.secondarySystemFill.cgColor)
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates automatic capsule fallback")
    func buildCreatesAutomaticCapsuleFallback() throws {
        // Given
        let snapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            observation: .init(semantics: .visualEffect(.automaticCapsule))
        )
        var builder = LayerWireframeBuilder(contentSnapshots: [:], webViewSlotIDs: [])

        // When
        let result = builder.build(from: snapshot, textInput: nil, cornerRadius: nil)
        let output = try #require(result)

        // Then
        guard case .shapeWireframe(let wireframe) = output.wireframe else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(
            wireframe.shapeStyle?.backgroundColor == hexString(from: UIColor.systemBackground.cgColor)
        )
        #expect(wireframe.shapeStyle?.cornerRadius == 20)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates hidden placeholder for private layer")
    func buildCreatesHiddenPlaceholderForPrivateLayer() throws {
        // Given
        let snapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            isPrivate: true
        )
        var builder = LayerWireframeBuilder(contentSnapshots: [:], webViewSlotIDs: [])

        // When
        let result = builder.build(
            from: snapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let output = try #require(result)

        // Then
        guard case .placeholderWireframe(let wireframe) = output.wireframe else {
            Issue.record("Expected a placeholder wireframe")
            return
        }

        #expect(wireframe.id == Int64(namespace: .placeholder, replayID: snapshot.replayID))
        #expect(wireframe.label == "Hidden")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build hides embedded content for a private layer")
    func buildHidesEmbeddedContentForPrivateLayer() throws {
        // Given
        let snapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            isPrivate: true
        )
        var builder = LayerWireframeBuilder(
            contentSnapshots: [:],
            webViewSlotIDs: [],
            embeddedContentSlots: [snapshot.replayID: "embedded-slot"]
        )

        // When
        _ = builder.build(
            from: snapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let hiddenEmbeddedContentWireframes = builder.makeHiddenEmbeddedContentWireframes()

        // Then
        guard case .embeddedContentWireframe(let hiddenWireframe) = try #require(hiddenEmbeddedContentWireframes.first) else {
            Issue.record("Expected a hidden embedded content wireframe")
            return
        }
        #expect(hiddenEmbeddedContentWireframes.count == 1)
        #expect(hiddenWireframe.id == Int64(namespace: .embeddedContent, replayID: snapshot.replayID))
        #expect(hiddenWireframe.slotId == "embedded-slot")
        #expect(hiddenWireframe.isVisible == false)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build tracks visible and hidden webviews")
    func buildTracksVisibleAndHiddenWebViews() throws {
        // Given
        let slotID = 42
        let hiddenSlotID = 43
        let frame = CGRect(x: 10, y: 20, width: 60, height: 40)
        let snapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: frame,
            observation: .init(semantics: .webView(.init(slotID: slotID, slotFrame: frame)))
        )
        var builder = LayerWireframeBuilder(
            contentSnapshots: [:],
            webViewSlotIDs: [slotID, hiddenSlotID]
        )

        // When
        let result = builder.build(
            from: snapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let output = try #require(result)
        let hiddenWireframes = builder.makeHiddenWebViewWireframes()

        // Then
        guard case .webviewWireframe(let wireframe) = output.wireframe,
              case .webviewWireframe(let hiddenWireframe) = try #require(hiddenWireframes.first) else {
            Issue.record("Expected webview wireframes")
            return
        }

        #expect(wireframe.id == Int64(slotID))
        #expect(wireframe.slotId == String(slotID))
        #expect(wireframe.isVisible == true)
        #expect(hiddenWireframes.count == 1)
        #expect(hiddenWireframe.slotId == String(hiddenSlotID))
        #expect(hiddenWireframe.isVisible == false)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build emits embedded content visibility state")
    func buildEmitsEmbeddedContentVisibilityState() throws {
        // Given
        let replayID: Int64 = 42
        let hiddenReplayID: Int64 = 43
        let slotID = "visible-slot"
        let hiddenSlotID = "hidden-slot"
        let snapshot = CALayerSnapshot.mockWith(
            replayID: replayID,
            absoluteFrame: CGRect(x: 10, y: 20, width: 60, height: 40),
            observation: .init(semantics: .embeddedContent(.init(slotID: slotID)))
        )
        var builder = LayerWireframeBuilder(
            contentSnapshots: [:],
            webViewSlotIDs: [],
            embeddedContentSlots: [
                replayID: slotID,
                hiddenReplayID: hiddenSlotID
            ]
        )

        // When
        let result = builder.build(
            from: snapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let output = try #require(result)
        let hiddenWireframes = builder.makeHiddenEmbeddedContentWireframes()

        // Then
        guard case .embeddedContentWireframe(let wireframe) = output.wireframe,
              case .embeddedContentWireframe(let hiddenWireframe) = try #require(hiddenWireframes.first) else {
            Issue.record("Expected embedded content wireframes")
            return
        }

        #expect(wireframe.id == Int64(namespace: .embeddedContent, replayID: replayID))
        #expect(wireframe.slotId == slotID)
        #expect(wireframe.isVisible == true)
        #expect(hiddenWireframes.count == 1)
        #expect(hiddenWireframe.id == Int64(namespace: .embeddedContent, replayID: hiddenReplayID))
        #expect(hiddenWireframe.slotId == hiddenSlotID)
        #expect(hiddenWireframe.isVisible == false)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates image resource for content snapshot")
    func buildCreatesImageResourceForContentSnapshot() throws {
        // Given
        let frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        let snapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: frame
        )
        let contentSnapshot = ContentSnapshot.mockAny(
            image: UIImage.mockWith(color: .red),
            frame: frame,
            hasLayerSemantics: true,
            textAndInputPrivacyLevel: .maskSensitiveInputs,
            imagePrivacyLevel: .maskNone
        )
        var builder = LayerWireframeBuilder(
            contentSnapshots: [snapshot.replayID: .success(contentSnapshot)],
            webViewSlotIDs: []
        )

        // When
        let result = builder.build(
            from: snapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let output = try #require(result)

        // Then
        guard case .imageWireframe(let wireframe) = output.wireframe else {
            Issue.record("Expected an image wireframe")
            return
        }

        let resource = try #require(output.resource)
        #expect(wireframe.id == Int64(namespace: .image, replayID: snapshot.replayID))
        #expect(wireframe.resourceId == resource.calculateIdentifier())
        #expect(resource.calculateData().isEmpty == false)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates shape wireframe when content redacts to placeholder")
    func buildCreatesShapeWireframeWhenContentRedactsToPlaceholder() throws {
        // Given
        let frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        let snapshot = CALayerSnapshot.mockWith(replayID: 2, absoluteFrame: frame)
        let contentSnapshot = ContentSnapshot.mockAny(
            image: UIImage.mockWith(color: .red),
            frame: frame,
            layerClass: try imageLayerClass(),
            hasLayerSemantics: true,
            imagePrivacyLevel: .maskAll
        )
        var builder = LayerWireframeBuilder(
            contentSnapshots: [snapshot.replayID: .success(contentSnapshot)],
            webViewSlotIDs: []
        )

        // When
        let result = builder.build(
            from: snapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let output = try #require(result)

        // Then
        guard case .shapeWireframe(let wireframe) = output.wireframe else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(wireframe.shapeStyle?.backgroundColor == "#FF0000FF")
        #expect(output.resource == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build handles image semantics without snapshot results")
    func buildHandlesImageSemanticsWithoutSnapshotResults() throws {
        // Given
        let privateImage = CALayerSnapshot.mockWith(
            replayID: 2,
            observation: .init(semantics: .image(.init(hasContent: true, isContextual: false)))
        )
        let emptyImage = CALayerSnapshot.mockWith(
            replayID: 3,
            observation: .init(semantics: .image(.init(hasContent: false, isContextual: false)))
        )
        var builder = LayerWireframeBuilder(contentSnapshots: [:], webViewSlotIDs: [])

        // When
        let privateImageResult = builder.build(
            from: privateImage,
            textInput: nil,
            cornerRadius: nil
        )
        let privateImageOutput = try #require(privateImageResult)
        let emptyImageOutput = builder.build(from: emptyImage, textInput: nil, cornerRadius: nil)

        // Then
        guard case .placeholderWireframe(let wireframe) = privateImageOutput.wireframe else {
            Issue.record("Expected a placeholder wireframe")
            return
        }

        #expect(wireframe.label == "Image")
        #expect(emptyImageOutput == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build handles failed content snapshots")
    func buildHandlesFailedContentSnapshots() throws {
        // Given
        let timedOutSnapshot = CALayerSnapshot.mockWith(replayID: 2)
        let discardedSnapshot = CALayerSnapshot.mockWith(replayID: 3)
        var builder = LayerWireframeBuilder(
            contentSnapshots: [
                timedOutSnapshot.replayID: .failure(.timedOut),
                discardedSnapshot.replayID: .failure(.discarded)
            ],
            webViewSlotIDs: []
        )

        // When
        let timedOutResult = builder.build(
            from: timedOutSnapshot,
            textInput: nil,
            cornerRadius: nil
        )
        let timedOutOutput = try #require(timedOutResult)
        let discardedOutput = builder.build(
            from: discardedSnapshot,
            textInput: nil,
            cornerRadius: nil
        )

        // Then
        guard case .placeholderWireframe(let wireframe) = timedOutOutput.wireframe else {
            Issue.record("Expected a placeholder wireframe")
            return
        }

        #expect(wireframe.label == "Timed out")
        #expect(discardedOutput == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private func backgroundColor(in output: LayerWireframeBuilder.Output?) throws -> String? {
        guard case .shapeWireframe(let wireframe) = try #require(output?.wireframe) else {
            Issue.record("Expected a shape wireframe")
            return nil
        }
        return wireframe.shapeStyle?.backgroundColor
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private func cornerRadius(in output: LayerWireframeBuilder.Output?) throws -> Double? {
        guard case .shapeWireframe(let wireframe) = try #require(output?.wireframe) else {
            Issue.record("Expected a shape wireframe")
            return nil
        }
        return wireframe.shapeStyle?.cornerRadius
    }
}

private func imageLayerClass() throws -> AnyClass {
    try #require(NSClassFromString("SwiftUI.ImageLayer"))
}
#endif
