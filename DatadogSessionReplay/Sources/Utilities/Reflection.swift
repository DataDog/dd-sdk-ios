/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation

/// A `Reflection` object can initialize itself from a
/// ``Mirror`` instance.
internal protocol Reflection {
    init(_ mirror: Mirror) throws
}

extension Reflection {
    /// Creates `Self` by reflecting a subject.
    ///
    /// - Parameter subject: The instance for which to create a reflection.
    init(reflecting subject: Any) throws {
        let mirror = Mirror(reflecting: subject)
        try self.init(mirror)
    }
}

extension Mirror {
    /// Returns a specific descendant of the reflected subject, or throw an error
    /// if no such descendant exists of the expected type.
    ///
    /// This function is suitable for exploring the structure of a mirror in a
    /// REPL or playground, but is not intended to be efficient. The efficiency
    /// of finding each element in the argument list depends on the argument
    /// type and the capabilities of the each level of the mirror's `children`
    /// collections. Each string argument requires a linear search, and unless
    /// the underlying collection supports random-access traversal, each integer
    /// argument also requires a linear operation.
    /// 
    /// - Parameters:
    ///   - type: The expected component type.
    ///   - path: The mirror path component to access.
    /// - Returns: The descendant of this mirror specified by the given mirror
    ///   path components if such a descendant exists; otherwise, `nil`.
    // swiftlint:disable:next function_default_parameter_at_end
    func descendant<Value>(_ type: Value.Type = Value.self, path: MirrorPath) throws -> Value {
        guard let value = descendant(path) else {
            if let superclassMirror = superclassMirror {
                return try superclassMirror.descendant(type, path: path)
            }

            throw InternalError(description: "not found at \(path)")
        }

        if let value = value as? Value {
            return value
        }

        throw InternalError(description: "type mismatch at \(path)")
    }

    /// Returns a reflection descendant of the subject, or throw an error
    /// if no such descendant exists or if the child reflection fails.
    ///
    /// This function is suitable for exploring the structure of a mirror in a
    /// REPL or playground, but is not intended to be efficient. The efficiency
    /// of finding each element in the argument list depends on the argument
    /// type and the capabilities of the each level of the mirror's `children`
    /// collections. Each string argument requires a linear search, and unless
    /// the underlying collection supports random-access traversal, each integer
    /// argument also requires a linear operation.
    ///
    /// - Parameters:
    ///   - type: The expected component type.
    ///   - path: The mirror path component to access.
    /// - Returns: The descendant of this mirror specified by the given mirror
    ///   path components if such a descendant exists; otherwise, `nil`.
    // swiftlint:disable:next function_default_parameter_at_end
    func descendant<Value>(_ type: Value.Type = Value.self, path: MirrorPath) throws -> Value where Value: Reflection {
        guard let value = descendant(path) else {
            if let superclassMirror = superclassMirror {
                return try superclassMirror.descendant(type, path: path)
            }

            throw InternalError(description: "not found at \(path)")
        }

        let mirror = Mirror(reflecting: value)

        if mirror.displayStyle == .optional {
            return try mirror.descendant(Value.self, path: "some")
        }

        return try Value(mirror)
    }
}

extension Array: Reflection where Element: Reflection {
    init(_ mirror: Mirror) throws {
        guard mirror.displayStyle == .collection || mirror.displayStyle == .set else {
            throw InternalError(description: "type mismatch: not a collection")
        }

        self = try mirror.children.map { try Element(reflecting: $0.value) }
    }
}

extension Dictionary: Reflection where Key: Reflection, Value: Reflection {
    init(_ mirror: Mirror) throws where Key: Reflection {
        guard mirror.displayStyle == .dictionary else {
            throw InternalError(description: "type mismatch: not a dictionary")
        }

        self = try mirror.children.reduce(into: [:]) { result, child in
            guard let pair = child.value as? (Any, Any) else {
                throw InternalError(description: "type mismatch: not a key:value pair")
            }

            try result[Key(reflecting: pair.0)] = Value(reflecting: pair.1)
        }
    }
}

extension Reflection {
    /// `Self` with lazy access to members.
    typealias Lazy = LazyReflection<Self>
}

/// A reflection wrapper that perform mirroring lazily.
@dynamicMemberLookup
internal final class LazyReflection<R>: Reflection where R: Reflection {
    lazy var `lazy`: R? = load()
    private let load: () -> R?

    init(_ mirror: Mirror) throws {
        self.load = { try? R(mirror) }
    }

    subscript<T>(dynamicMember keyPath: KeyPath<R, T>) -> T? {
        self.lazy?[keyPath: keyPath]
    }
}

#endif
