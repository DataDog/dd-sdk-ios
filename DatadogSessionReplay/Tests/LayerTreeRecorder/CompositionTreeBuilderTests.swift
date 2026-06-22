/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import Testing

@_spi(Internal)
@testable import DatadogSessionReplay

@MainActor
struct CompositionTreeBuilderTests {
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
