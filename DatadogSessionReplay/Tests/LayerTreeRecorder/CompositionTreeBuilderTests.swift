/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import TestUtilities
import QuartzCore
import Testing
import UIKit

@_spi(Internal)
@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct CompositionTreeBuilderTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates background and content references for container")
    func buildCreatesBackgroundAndContentReferencesForContainer() throws {
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
        let containerSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 40),
            observation: .init(semantics: .gradient(gradient)),
            sublayers: [contentSnapshot]
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [containerSnapshot])
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            embeddedContentSlots: [:],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children == [
            .init(id: containerSnapshot.replayID, type: .layer)
        ])

        let layer = try #require(
            output.compositionTree.layers?.first { $0.id == containerSnapshot.replayID }
        )
        #expect(layer.children == [
            .init(id: .init(namespace: .shape, replayID: containerSnapshot.replayID), type: .wireframe),
            .init(id: .init(namespace: .shape, replayID: contentSnapshot.replayID), type: .wireframe)
        ])
        #expect(output.wireframes.count == 2)
        #expect(output.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates fallback and content references for automatic capsule")
    func buildCreatesFallbackAndContentReferencesForAutomaticCapsule() throws {
        // Given
        let contentSnapshot = CALayerSnapshot.mockWith(
            replayID: 3,
            absoluteFrame: CGRect(x: 20, y: 30, width: 80, height: 40),
            backgroundColor: UIColor.red.cgColor
        )
        let capsuleSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: 60),
            observation: .init(semantics: .visualEffect(.automaticCapsule)),
            sublayers: [contentSnapshot]
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [capsuleSnapshot])
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            embeddedContentSlots: [:],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        let layer = try #require(
            output.compositionTree.layers?.first { $0.id == capsuleSnapshot.replayID }
        )
        #expect(layer.children == [
            .init(id: .init(namespace: .shape, replayID: capsuleSnapshot.replayID), type: .wireframe),
            .init(id: .init(namespace: .shape, replayID: contentSnapshot.replayID), type: .wireframe)
        ])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates composition layer for leaf with modifiers")
    func buildCreatesCompositionLayerForLeafWithModifiers() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let leafLayer = CALayer()
        leafLayer.frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        leafLayer.backgroundColor = UIColor.red.cgColor
        leafLayer.opacity = 0.5
        rootLayer.addSublayer(leafLayer)

        let root = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let leaf = try #require(root.sublayers.first)
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [],
            embeddedContentSlots: [:],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        #expect(output.compositionTree.root.children == [
            .init(id: leaf.replayID, type: .layer)
        ])

        let layer = try #require(output.compositionTree.layers?.first)
        #expect(layer.id == leaf.replayID)
        #expect(layer.children == [
            .init(id: .init(namespace: .shape, replayID: leaf.replayID), type: .wireframe)
        ])
        #expect(output.wireframes.count == 1)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build applies inherited visual effect to descendant wireframe")
    func buildAppliesInheritedVisualEffectToDescendantWireframe() throws {
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
            embeddedContentSlots: [:],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        let wireframe = try #require(output.wireframes.first { wireframe in
            guard case .shapeWireframe(let shapeWireframe) = wireframe else {
                return false
            }
            return shapeWireframe.id == Int64(namespace: .shape, replayID: contentSnapshot.replayID)
        })
        guard case .shapeWireframe(let shapeWireframe) = wireframe else {
            Issue.record("Expected a shape wireframe")
            return
        }

        #expect(shapeWireframe.shapeStyle?.cornerRadius == 12)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build includes embedded content visibility state")
    func buildIncludesEmbeddedContentVisibilityState() throws {
        // Given
        let visibleReplayID: Int64 = 2
        let hiddenReplayID: Int64 = 3
        let visibleSnapshot = CALayerSnapshot.mockWith(
            replayID: visibleReplayID,
            absoluteFrame: CGRect(x: 10, y: 20, width: 30, height: 40),
            observation: .init(semantics: .embeddedContent(.init(slotID: "visible-slot")))
        )
        let builder = CompositionTreeBuilder(
            root: .mockRoot(sublayers: [visibleSnapshot]),
            webViewSlotIDs: [],
            embeddedContentSlots: [
                visibleReplayID: "visible-slot",
                hiddenReplayID: "hidden-slot"
            ],
            imageSnapshots: .init()
        )

        // When
        let output = builder.build()

        // Then
        let visibleWireframeID = Int64(namespace: .embeddedContent, replayID: visibleReplayID)
        let hiddenWireframeID = Int64(namespace: .embeddedContent, replayID: hiddenReplayID)
        #expect(output.compositionTree.root.children == [
            .init(id: visibleWireframeID, type: .wireframe)
        ])
        try #require(output.wireframes.count == 2)

        guard
            case .embeddedContentWireframe(let hiddenWireframe) = output.wireframes[0],
            case .embeddedContentWireframe(let visibleWireframe) = output.wireframes[1]
        else {
            Issue.record("Expected embedded content wireframes")
            return
        }

        #expect(hiddenWireframe.id == hiddenWireframeID)
        #expect(hiddenWireframe.slotId == "hidden-slot")
        #expect(hiddenWireframe.isVisible == false)
        #expect(visibleWireframe.id == visibleWireframeID)
        #expect(visibleWireframe.slotId == "visible-slot")
        #expect(visibleWireframe.isVisible == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build can be reused without accumulating output state")
    func buildCanBeReusedWithoutAccumulatingOutputState() throws {
        // Given
        let slotID = 42
        let hiddenSlotID = 43
        let frame = CGRect(x: 10, y: 20, width: 60, height: 40)
        let webViewSnapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: frame,
            observation: .init(semantics: .webView(.init(slotID: slotID, slotFrame: frame)))
        )
        let root = CALayerSnapshot.mockRoot(sublayers: [webViewSnapshot])
        let builder = CompositionTreeBuilder(
            root: root,
            webViewSlotIDs: [slotID, hiddenSlotID],
            embeddedContentSlots: [:],
            imageSnapshots: .init()
        )

        // When
        let firstOutput = builder.build()
        let secondOutput = builder.build()

        // Then
        #expect(firstOutput.compositionTree.root.children == [
            .init(id: Int64(slotID), type: .wireframe)
        ])
        #expect(secondOutput.compositionTree.root.children == firstOutput.compositionTree.root.children)
        #expect(visibleWebViewSlotIDs(in: firstOutput.wireframes) == [String(slotID)])
        #expect(visibleWebViewSlotIDs(in: secondOutput.wireframes) == [String(slotID)])
        #expect(hiddenWebViewSlotIDs(in: firstOutput.wireframes) == [String(hiddenSlotID)])
        #expect(hiddenWebViewSlotIDs(in: secondOutput.wireframes) == [String(hiddenSlotID)])
        #expect(firstOutput.resources.isEmpty)
        #expect(secondOutput.resources.isEmpty)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private func visibleWebViewSlotIDs(in wireframes: [SRWireframe]) -> [String] {
        webViewSlotIDs(in: wireframes, isVisible: true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private func hiddenWebViewSlotIDs(in wireframes: [SRWireframe]) -> [String] {
        webViewSlotIDs(in: wireframes, isVisible: false)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private func webViewSlotIDs(in wireframes: [SRWireframe], isVisible: Bool) -> [String] {
        wireframes.compactMap { wireframe in
            guard case .webviewWireframe(let value) = wireframe, value.isVisible == isVisible else {
                return nil
            }
            return value.slotId
        }
    }
}
#endif
