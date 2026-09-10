/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import TestUtilities
import Testing
import DatadogInternal
import UIKit

@testable import DatadogRUM

@Suite(.datadogTesting)
@MainActor
struct HeatmapIdentifierStoreTests {
    @Test
    func setHeatmapIdentifiersReplacesCurrentSnapshot() {
        // given
        let store = HeatmapIdentifierStore()
        let layer1 = CALayer()
        let layer2 = CALayer()
        let id1 = HeatmapIdentifier(rawValue: "aaa")
        let id2 = HeatmapIdentifier(rawValue: "bbb")

        // when
        store.setHeatmapIdentifiers(
            [ObjectIdentifier(layer1): id1],
            requiresDescendantLookup: false
        )
        store.setHeatmapIdentifiers(
            [ObjectIdentifier(layer2): id2],
            requiresDescendantLookup: true
        )

        // then
        #expect(store.heatmapIdentifier(for: ObjectIdentifier(layer1)) == nil)
        #expect(store.heatmapIdentifier(for: ObjectIdentifier(layer2)) == id2)
        #expect(store.requiresDescendantLookup)
    }
}
#endif
