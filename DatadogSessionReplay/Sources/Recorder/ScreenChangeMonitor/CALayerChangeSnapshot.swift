/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Represents the snapshot of layer changes accumulated over a time interval,
// keyed by layer identity. Provides lookup of changed aspects for a `CALayer` and
// supports iteration over all recorded changes.

#if os(iOS)
import QuartzCore

internal struct CALayerChangeSnapshot: Equatable {
    private let changes: [ObjectIdentifier: CALayerChange]

    init(_ changes: [ObjectIdentifier: CALayerChange]) {
        self.changes = changes
    }

    func aspects(for layer: CALayer) -> CALayerChange.Aspect.Set? {
        changes[ObjectIdentifier(layer)]?.aspects
    }

    func removingDeallocatedLayers() -> CALayerChangeSnapshot {
        let changes = self.changes.filter {
            $1.layer != nil
        }
        return CALayerChangeSnapshot(changes)
    }
}

extension CALayerChangeSnapshot: Collection {
    typealias Index = Dictionary<ObjectIdentifier, CALayerChange>.Values.Index
    typealias Element = Dictionary<ObjectIdentifier, CALayerChange>.Values.Element

    var startIndex: Index { changes.values.startIndex }
    var endIndex: Index { changes.values.endIndex }

    func index(after i: Index) -> Index {
        changes.values.index(after: i)
    }

    subscript(position: Index) -> Element {
        changes.values[position]
    }
}

extension CALayerChangeSnapshot: CustomStringConvertible {
    var description: String {
        let layerCount = self.count

        var displayCount = 0
        var drawCount = 0
        var layoutCount = 0

        for aspects in self.map(\.aspects) {
            if aspects.contains(.display) { displayCount += 1 }
            if aspects.contains(.draw) { drawCount += 1 }
            if aspects.contains(.layout) { layoutCount += 1 }
        }

        return "(layers:\(layerCount),displays:\(displayCount),draws:\(drawCount),layouts:\(layoutCount))"
    }
}
#endif
