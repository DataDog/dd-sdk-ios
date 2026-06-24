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

// MARK: - `Equatable` Conformance

extension SRCompositionLayer: Equatable {
    public static func == (lhs: SRCompositionLayer, rhs: SRCompositionLayer) -> Bool {
        return lhs.children == rhs.children
            && lhs.compositeOperation == rhs.compositeOperation
            && lhs.height == rhs.height
            && lhs.id == rhs.id
            && lhs.modifiers == rhs.modifiers
            && lhs.width == rhs.width
            && lhs.x == rhs.x
            && lhs.y == rhs.y
    }
}

extension SRCompositionLayerChild: Equatable {
    public static func == (lhs: SRCompositionLayerChild, rhs: SRCompositionLayerChild) -> Bool {
        return lhs.id == rhs.id && lhs.type == rhs.type
    }
}

extension SRCompositionLayerBackgroundMaterialModifier: Equatable {
    public static func == (
        lhs: SRCompositionLayerBackgroundMaterialModifier,
        rhs: SRCompositionLayerBackgroundMaterialModifier
    ) -> Bool {
        return lhs.kind == rhs.kind
    }
}

extension SRCompositionLayerBrightnessBiasModifier: Equatable {
    public static func == (
        lhs: SRCompositionLayerBrightnessBiasModifier,
        rhs: SRCompositionLayerBrightnessBiasModifier
    ) -> Bool {
        return lhs.value == rhs.value
    }
}

extension SRCompositionLayerClipModifier: Equatable {
    public static func == (
        lhs: SRCompositionLayerClipModifier,
        rhs: SRCompositionLayerClipModifier
    ) -> Bool {
        return lhs.fillRule == rhs.fillRule && lhs.path == rhs.path
    }
}

extension SRCompositionLayerColorMatrixModifier: Equatable {
    public static func == (
        lhs: SRCompositionLayerColorMatrixModifier,
        rhs: SRCompositionLayerColorMatrixModifier
    ) -> Bool {
        return lhs.matrix == rhs.matrix
    }
}

extension SRCompositionLayerGaussianBlurModifier: Equatable {
    public static func == (
        lhs: SRCompositionLayerGaussianBlurModifier,
        rhs: SRCompositionLayerGaussianBlurModifier
    ) -> Bool {
        return lhs.radius == rhs.radius
    }
}

extension SRCompositionLayerOpacityModifier: Equatable {
    public static func == (
        lhs: SRCompositionLayerOpacityModifier,
        rhs: SRCompositionLayerOpacityModifier
    ) -> Bool {
        return lhs.value == rhs.value
    }
}

extension SRCompositionLayerSaturateModifier: Equatable {
    public static func == (
        lhs: SRCompositionLayerSaturateModifier,
        rhs: SRCompositionLayerSaturateModifier
    ) -> Bool {
        return lhs.value == rhs.value
    }
}

extension SRCompositionLayerModifier: Equatable {
    public static func == (lhs: SRCompositionLayerModifier, rhs: SRCompositionLayerModifier) -> Bool {
        switch (lhs, rhs) {
        case let (.compositionLayerClipModifier(lhs), .compositionLayerClipModifier(rhs)):
            return lhs == rhs
        case let (.compositionLayerOpacityModifier(lhs), .compositionLayerOpacityModifier(rhs)):
            return lhs == rhs
        case let (.compositionLayerColorMatrixModifier(lhs), .compositionLayerColorMatrixModifier(rhs)):
            return lhs == rhs
        case let (.compositionLayerGaussianBlurModifier(lhs), .compositionLayerGaussianBlurModifier(rhs)):
            return lhs == rhs
        case let (.compositionLayerBrightnessBiasModifier(lhs), .compositionLayerBrightnessBiasModifier(rhs)):
            return lhs == rhs
        case let (.compositionLayerSaturateModifier(lhs), .compositionLayerSaturateModifier(rhs)):
            return lhs == rhs
        case let (.compositionLayerBackgroundMaterialModifier(lhs), .compositionLayerBackgroundMaterialModifier(rhs)):
            return lhs == rhs
        case (.compositionLayerClipModifier, _),
            (.compositionLayerOpacityModifier, _),
            (.compositionLayerColorMatrixModifier, _),
            (.compositionLayerGaussianBlurModifier, _),
            (.compositionLayerBrightnessBiasModifier, _),
            (.compositionLayerSaturateModifier, _),
            (.compositionLayerBackgroundMaterialModifier, _):
            return false
        }
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
