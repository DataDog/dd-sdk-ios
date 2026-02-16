/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Represents the layer changes accumulated over a time interval,
// keyed by layer identity. Provides lookup of changed aspects for a `CALayer` and
// supports iteration over all recorded changes.

#if os(iOS)
import QuartzCore

internal struct CALayerChangeset: Sendable, Equatable {
    var isEmpty: Bool {
        changes.isEmpty
    }

    private var changes: [ObjectIdentifier: CALayerChange]

    init(_ changes: [ObjectIdentifier: CALayerChange] = [:]) {
        self.changes = changes
    }

    func aspects(for layer: CALayerReference) -> CALayerChange.Aspect.Set? {
        guard
            let identifier = layer.identifier,
            let change = changes[identifier],
            change.layer.identifier == identifier // ObjectIdentifier is only valid during the lifetime of an instance
        else {
            return nil
        }
        return change.aspects
    }

    mutating func merge(_ other: CALayerChangeset) {
        changes.merge(other.changes) {
            // ObjectIdentifier is only valid during the lifetime of an instance
            guard $0.layer == $1.layer else {
                return $1
            }
            return CALayerChange(layer: $1.layer, aspects: $0.aspects.union($1.aspects))
        }
    }

    mutating func removeDeallocatedLayers() {
        changes = changes.filter(\.value.layer.isAlive)
    }

    mutating func removeAll() {
        changes.removeAll()
    }
}

extension CALayerChangeset: CustomStringConvertible {
    var description: String {
        let layerCount = changes.count

        var displayCount = 0
        var drawCount = 0
        var layoutCount = 0

        for aspects in changes.values.map(\.aspects) {
            if aspects.contains(.display) { displayCount += 1 }
            if aspects.contains(.draw) { drawCount += 1 }
            if aspects.contains(.layout) { layoutCount += 1 }
        }

        return "(layers: \(layerCount),displays: \(displayCount),draws: \(drawCount),layouts: \(layoutCount))"
    }
}
#endif
