/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

extension SRCompositionTree {
    func mutations(from otherTree: SRCompositionTree) throws -> SRCompositionTreeMutationData? {
        let oldLayers = otherTree.layersSortedByID
        let newLayers = layersSortedByID
        let diff = try computeDiff(oldArray: oldLayers, newArray: newLayers)

        let root = root.isDifferent(than: otherTree.root) ? root : nil
        let adds = diff.adds.map(\.new)
        let removes = diff.removes.map(\.id)
        let updates = try diff.updates.map { update in
            return try update.to.mutations(from: update.from)
        }

        guard root != nil || !adds.isEmpty || !removes.isEmpty || !updates.isEmpty else {
            return nil
        }

        return SRCompositionTreeMutationData(
            adds: adds.isEmpty ? nil : adds,
            removes: removes.isEmpty ? nil : removes,
            root: root,
            updates: updates.isEmpty ? nil : updates
        )
    }

    private var layersSortedByID: [SRCompositionLayer] {
        return (layers ?? []).sorted { $0.id < $1.id }
    }
}

// MARK: - `Diffable` Conformance

extension SRCompositionLayer: Diffable {
    func isDifferent(than otherElement: SRCompositionLayer) -> Bool {
        return self != otherElement
    }
}

// MARK: - Resolving Mutations

internal enum CompositionLayerMutationError: Error, Equatable {
    /// Indicates an attempt of computing mutation for composition layers that have different `id`.
    case idMismatch
}

private func use<V: Equatable>(_ new: V?, ifDifferentThan old: V?) -> V? {
    return new != old ? new : nil
}

private func use(
    _ new: [SRCompositionLayerModifier]?,
    ifDifferentThan old: [SRCompositionLayerModifier]?
) -> [SRCompositionLayerModifier]? {
    return new != old ? new ?? [] : nil
}

private func use(
    _ new: SRCompositionLayer.CompositeOperation?,
    ifDifferentThan old: SRCompositionLayer.CompositeOperation?
) -> SRCompositionLayerUpdate.CompositeOperation? {
    guard new != old else {
        return nil
    }
    return new.map(SRCompositionLayerUpdate.CompositeOperation.init) ?? .sourceOver
}

extension SRCompositionLayerUpdate.CompositeOperation {
    init(_ operation: SRCompositionLayer.CompositeOperation) {
        switch operation {
        case .sourceOver:
            self = .sourceOver
        case .destinationIn:
            self = .destinationIn
        case .destinationOut:
            self = .destinationOut
        case .plusDarker:
            self = .plusDarker
        }
    }
}

extension SRCompositionLayer {
    func mutations(from otherLayer: SRCompositionLayer) throws -> SRCompositionLayerUpdate {
        guard otherLayer.id == id else {
            throw CompositionLayerMutationError.idMismatch
        }

        return SRCompositionLayerUpdate(
            children: use(children, ifDifferentThan: otherLayer.children),
            compositeOperation: use(compositeOperation, ifDifferentThan: otherLayer.compositeOperation),
            height: use(height, ifDifferentThan: otherLayer.height),
            id: id,
            modifiers: use(modifiers, ifDifferentThan: otherLayer.modifiers),
            width: use(width, ifDifferentThan: otherLayer.width),
            x: use(x, ifDifferentThan: otherLayer.x),
            y: use(y, ifDifferentThan: otherLayer.y)
        )
    }
}
#endif
