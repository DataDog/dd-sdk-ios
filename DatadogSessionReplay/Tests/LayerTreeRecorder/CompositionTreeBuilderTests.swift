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
