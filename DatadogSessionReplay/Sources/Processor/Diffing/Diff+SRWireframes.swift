/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

// MARK: - `Diffable` Conformance

extension SRWireframe: Diffable {
    var id: DiffableID {
        switch self {
        case .shapeWireframe(let wireframe):
            return wireframe.id
        case .imageWireframe(let wireframe):
            return wireframe.id
        case .textWireframe(let wireframe):
            return wireframe.id
        case .placeholderWireframe(let wireframe):
            return wireframe.id
        case .webviewWireframe(let wireframe):
            return wireframe.id
        }
    }

    func isDifferent(than otherElement: SRWireframe) -> Bool {
        switch (self, otherElement) {
        case let (.shapeWireframe(this), .shapeWireframe(other)):
            return this.hashValue != other.hashValue
        case let (.textWireframe(this), .textWireframe(other)):
            return this.hashValue != other.hashValue
        case let (.imageWireframe(this), .imageWireframe(other)):
            return this.hashValue != other.hashValue
        case let (.placeholderWireframe(this), .placeholderWireframe(other)):
            return this.hashValue != other.hashValue
        default:
            return true
        }
    }
}

// MARK: - Resolving Mutations

internal typealias WireframeMutation = SRIncrementalSnapshotRecord.Data.MutationData.Updates

internal enum WireframeMutationError: Error {
    /// Indicates an attempt of computing mutation for wireframes that have different `id`.
    case idMismatch
    /// Indicates an attempt of computing mutation for wireframes that have different type.
    case typeMismatch
}

internal protocol MutableWireframe {
    /// Returns `WireframeMutation` that needs to be applied to `self` to result with `otherWireframe`.
    func mutations(from otherWireframe: SRWireframe) throws -> WireframeMutation
}

/// Syntactic sugar to return `new` value if it's different than `old`.
private func use<V: Equatable>(_ new: V?, ifDifferentThan old: V?) -> V? {
    return new == old ? nil : new
}

extension SRWireframe: MutableWireframe {
    func mutations(from otherWireframe: SRWireframe) throws -> WireframeMutation {
        switch self {
        case .shapeWireframe(let this):
            return try this.mutations(from: otherWireframe)
        case .imageWireframe(let this):
            return try this.mutations(from: otherWireframe)
        case .textWireframe(let this):
            return try this.mutations(from: otherWireframe)
        case .placeholderWireframe(let this):
            return try this.mutations(from: otherWireframe)
        case .webviewWireframe(let this):
            return try this.mutations(from: otherWireframe)
        }
    }
}

extension SRShapeWireframe: MutableWireframe {
    func mutations(from otherWireframe: SRWireframe) throws -> WireframeMutation {
        guard case .shapeWireframe(let other) = otherWireframe else {
            throw WireframeMutationError.typeMismatch
        }
        guard other.id == id else {
            throw WireframeMutationError.idMismatch
        }

        return .shapeWireframeUpdate(
            value: .init(
                border: use(border, ifDifferentThan: other.border),
                clip: use(clip, ifDifferentThan: other.clip),
                height: use(height, ifDifferentThan: other.height),
                id: id,
                shapeStyle: use(shapeStyle, ifDifferentThan: other.shapeStyle),
                width: use(width, ifDifferentThan: other.width),
                x: use(x, ifDifferentThan: other.x),
                y: use(y, ifDifferentThan: other.y)
            )
        )
    }
}

extension SRPlaceholderWireframe: MutableWireframe {
    func mutations(from otherWireframe: SRWireframe) throws -> WireframeMutation {
        guard case .placeholderWireframe(let other) = otherWireframe else {
            throw WireframeMutationError.typeMismatch
        }
        guard other.id == id else {
            throw WireframeMutationError.idMismatch
        }

        return .placeholderWireframeUpdate(
            value: .init(
                clip: use(clip, ifDifferentThan: other.clip),
                height: use(height, ifDifferentThan: other.height),
                id: id,
                width: use(width, ifDifferentThan: other.width),
                x: use(x, ifDifferentThan: other.x),
                y: use(y, ifDifferentThan: other.y)
            )
        )
    }
}

extension SRImageWireframe: MutableWireframe {
    func mutations(from otherWireframe: SRWireframe) throws -> WireframeMutation {
        guard case .imageWireframe(let other) = otherWireframe else {
            throw WireframeMutationError.typeMismatch
        }
        guard other.id == id else {
            throw WireframeMutationError.idMismatch
        }

        return .imageWireframeUpdate(
            value: .init(
                base64: use(base64, ifDifferentThan: other.base64),
                border: use(border, ifDifferentThan: other.border),
                clip: use(clip, ifDifferentThan: other.clip),
                height: use(height, ifDifferentThan: other.height),
                id: id,
                isEmpty: use(isEmpty, ifDifferentThan: other.isEmpty),
                mimeType: use(mimeType, ifDifferentThan: other.mimeType),
                shapeStyle: use(shapeStyle, ifDifferentThan: other.shapeStyle),
                width: use(width, ifDifferentThan: other.width),
                x: use(x, ifDifferentThan: other.x),
                y: use(y, ifDifferentThan: other.y)
            )
        )
    }
}

extension SRTextWireframe: MutableWireframe {
    func mutations(from otherWireframe: SRWireframe) throws -> WireframeMutation {
        guard case .textWireframe(let other) = otherWireframe else {
            throw WireframeMutationError.typeMismatch
        }
        guard other.id == id else {
            throw WireframeMutationError.idMismatch
        }

        return .textWireframeUpdate(
            value: .init(
                border: use(border, ifDifferentThan: other.border),
                clip: use(clip, ifDifferentThan: other.clip),
                height: use(height, ifDifferentThan: other.height),
                id: id,
                shapeStyle: use(shapeStyle, ifDifferentThan: other.shapeStyle),
                text: use(text, ifDifferentThan: other.text),
                textPosition: use(textPosition, ifDifferentThan: other.textPosition),
                textStyle: use(textStyle, ifDifferentThan: other.textStyle),
                width: use(width, ifDifferentThan: other.width),
                x: use(x, ifDifferentThan: other.x),
                y: use(y, ifDifferentThan: other.y)
            )
        )
    }
}

extension SRWebviewWireframe: MutableWireframe {
    func mutations(from otherWireframe: SRWireframe) throws -> WireframeMutation {
        guard case .webviewWireframe(let other) = otherWireframe else {
            throw WireframeMutationError.typeMismatch
        }
        guard other.id == id, other.slotId == slotId else {
            throw WireframeMutationError.idMismatch
        }

        return .webviewWireframeUpdate(
            value: .init(
                border: use(border, ifDifferentThan: other.border),
                clip: use(clip, ifDifferentThan: other.clip),
                height: use(height, ifDifferentThan: other.height),
                id: id,
                shapeStyle: use(shapeStyle, ifDifferentThan: other.shapeStyle),
                slotId: slotId,
                width: use(width, ifDifferentThan: other.width),
                x: use(x, ifDifferentThan: other.x),
                y: use(y, ifDifferentThan: other.y)
            )
        )
    }
}

extension SRImageWireframe {
    @_spi(Internal)
    public static func == (lhs: SRImageWireframe, rhs: SRImageWireframe) -> Bool {
        return lhs.id == rhs.id
            && lhs.resourceId == rhs.resourceId
            && lhs.border == rhs.border
            && lhs.clip == rhs.clip
            && lhs.height == rhs.height
            && lhs.isEmpty == rhs.isEmpty
            && lhs.mimeType == rhs.mimeType
            && lhs.shapeStyle == rhs.shapeStyle
            && lhs.width == rhs.width
            && lhs.x == rhs.x
            && lhs.y == rhs.y
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(resourceId)
        hasher.combine(border)
        hasher.combine(clip)
        hasher.combine(height)
        hasher.combine(isEmpty)
        hasher.combine(mimeType)
        hasher.combine(shapeStyle)
        hasher.combine(width)
        hasher.combine(x)
        hasher.combine(y)
    }
}
#endif
