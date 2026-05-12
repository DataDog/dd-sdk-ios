/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import Testing

@testable import DatadogSessionReplay

struct CALayerChangesetTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Display and draw changes are content changes")
    func hasContentChanges() {
        // Given
        let displayLayer = CALayer()
        let drawLayer = CALayer()
        let layoutLayer = CALayer()

        let changeset = CALayerChangeset(
            [
                ObjectIdentifier(displayLayer): CALayerChange(layer: .init(displayLayer), aspects: .display),
                ObjectIdentifier(drawLayer): CALayerChange(layer: .init(drawLayer), aspects: .draw),
                ObjectIdentifier(layoutLayer): CALayerChange(layer: .init(layoutLayer), aspects: .layout)
            ]
        )

        // Then
        #expect(changeset.hasContentChanges(for: .init(displayLayer)))
        #expect(changeset.hasContentChanges(for: .init(drawLayer)))
        #expect(!changeset.hasContentChanges(for: .init(layoutLayer)))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Deallocated layers do not return stale aspects")
    func deallocatedLayerDoesNotReturnStaleAspects() {
        // Given
        var layer: CALayer? = CALayer()
        let layerReference = CALayerReference(layer!)
        let changeset = CALayerChangeset(
            [ObjectIdentifier(layer!): CALayerChange(layer: layerReference, aspects: .display)]
        )

        // When
        layer = nil

        // Then
        #expect(changeset.aspects(for: layerReference) == nil)
        #expect(!changeset.hasContentChanges(for: layerReference))
    }
}
#endif
