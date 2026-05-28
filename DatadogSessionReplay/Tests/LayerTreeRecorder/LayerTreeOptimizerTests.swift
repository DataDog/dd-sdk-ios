/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
import QuartzCore
import Testing

@_spi(Internal)
import TestUtilities

@_spi(Internal)
@testable import DatadogSessionReplay

@MainActor
struct LayerTreeOptimizerTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Sorts sublayers by zPosition recursively")
    func sortsSublayersByZPositionRecursively() throws {
        // Given
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        let parentA = CALayer()
        parentA.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        parentA.zPosition = 0

        let childA1 = CALayer()
        childA1.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        childA1.zPosition = 1

        let childA2 = CALayer()
        childA2.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        childA2.zPosition = -1

        parentA.addSublayer(childA1)
        parentA.addSublayer(childA2)

        let parentB = CALayer()
        parentB.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        parentB.zPosition = -5

        root.addSublayer(parentA)
        root.addSublayer(parentB)

        let captured = try #require(CALayerSnapshot(from: root, in: .mockAny()))
        let snapshot = LayerTreeSnapshot.mockWith(root: captured)

        // When
        let optimized = LayerTreeOptimizer().optimize(snapshot)

        // Then
        #expect(optimized.root.sublayers.map(\.zPosition) == [-5, 0])
        let sortedParent = try #require(optimized.root.sublayers.last)
        #expect(sortedParent.sublayers.map(\.zPosition) == [-1, 1])
    }
}
#endif
