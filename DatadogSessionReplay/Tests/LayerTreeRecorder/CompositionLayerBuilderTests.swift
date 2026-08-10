/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Testing
import UIKit

@_spi(Internal)
@testable import DatadogSessionReplay

@MainActor
struct CompositionLayerBuilderTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build maps geometry and children")
    func buildMapsGeometryAndChildren() {
        // Given
        let snapshot = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 100, height: CGFloat(1) / 3)
        )
        let children = [SRCompositionLayerChild(id: 3, type: .wireframe)]
        let builder = CompositionLayerBuilder(maskSnapshots: [:])

        // When
        let output = builder.build(from: snapshot, children: children)

        // Then
        #expect(output.layer.id == snapshot.replayID)
        #expect(output.layer.x == 10)
        #expect(output.layer.y == 20)
        #expect(output.layer.width == 100)
        #expect(output.layer.height == 1)
        #expect(output.layer.children == children)
        #expect(output.resource == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Build creates mask image resource")
    func buildCreatesMaskImageResource() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

        let containerLayer = CALayer()
        containerLayer.frame = CGRect(x: 10, y: 20, width: 100, height: 40)

        let leafLayer = CALayer()
        leafLayer.frame = containerLayer.bounds
        leafLayer.backgroundColor = UIColor.red.cgColor
        containerLayer.addSublayer(leafLayer)

        let maskLayer = CALayer()
        maskLayer.bounds = containerLayer.bounds
        maskLayer.backgroundColor = UIColor.black.cgColor
        containerLayer.mask = maskLayer

        rootLayer.addSublayer(containerLayer)

        let root = try #require(CALayerSnapshot(from: rootLayer, in: .mockAny()))
        let snapshot = try #require(root.sublayers.first)
        let mask = try #require(snapshot.mask)
        let maskSnapshot = MaskSnapshot.mockAny(image: UIImage.mockWith(color: .black))
        let builder = CompositionLayerBuilder(
            maskSnapshots: [mask.replayID: .success(maskSnapshot)]
        )

        // When
        let output = builder.build(from: snapshot, children: [])

        // Then
        let resource = try #require(output.resource)
        let modifier = try #require(output.layer.modifiers?.first)

        guard case .compositionLayerMaskImageModifier(let maskImageModifier) = modifier else {
            Issue.record("Expected a mask image modifier")
            return
        }

        #expect(maskImageModifier.resourceId == resource.calculateIdentifier())
    }
}
#endif
