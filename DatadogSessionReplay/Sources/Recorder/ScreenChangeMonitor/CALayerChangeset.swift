/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore

/// Layer changes collected over one delivery window.
///
/// Changes are keyed by layer identity. Callers can ask which aspects changed
/// for a live layer reference.
internal struct CALayerChangeset: Sendable, Equatable {
    var isEmpty: Bool {
        changes.isEmpty
    }

    var contentChanges: [CALayerChange] {
        changes.values.filter { change in
            change.aspects.contains(.display) || change.aspects.contains(.draw)
        }
    }

    private let changes: [ObjectIdentifier: CALayerChange]

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

    func hasContentChanges(for layer: CALayerReference) -> Bool {
        guard let aspects = aspects(for: layer) else {
            return false
        }
        return aspects.contains(.display) || aspects.contains(.draw)
    }

    func hasChanges(for layer: CALayerReference) -> Bool {
        aspects(for: layer) != nil
    }

    func hasChanges<S: Sequence>(for layers: S) -> Bool where S.Element == CALayerReference {
        layers.contains { hasChanges(for: $0) }
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
