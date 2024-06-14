/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal protocol Reflection {
    init(_ mirror: Mirror) throws
}

extension Reflection {
    init(reflecting subject: Any) throws {
        let mirror = Mirror(reflecting: subject)
        try self.init(mirror)
    }
}

extension Array: Reflection where Element: Reflection {
    init(_ mirror: Mirror) throws {
        guard mirror.displayStyle == .collection else {
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

extension Mirror {
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

extension Reflection {
    typealias Lazy = LazyReflection<Self>
}

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
