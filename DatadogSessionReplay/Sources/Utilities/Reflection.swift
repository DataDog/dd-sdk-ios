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
    init(_ mirror: Mirror) throws {
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
    func descendant<Value>(_ type: Value.Type = Value.self, path: MirrorPath) throws -> Value {
        let child = try descendant(path) ?? superclassMirror?.descendant(type, path: path)
        guard let value = child as? Value else {
            throw InternalError(description: "type mismatch at \(path)")
        }
        return value
    }

    func descendant<Value>(_ type: Value.Type = Value.self, path: MirrorPath) throws -> Value where Value: Reflection {
        let child = try descendant(path) ?? superclassMirror?.descendant(type, path: path)

        guard let child = child as? Any else {
            throw InternalError(description: "not found at \(path)")
        }

        let mirror = Mirror(reflecting: child)

        guard mirror.displayStyle == .optional else {
            return try Value(mirror)
        }

        return try mirror.descendant(Value.self, path: "some")
    }
}

extension Reflection {
    typealias Lazy = LazyReflection<Self>
}

@dynamicMemberLookup
internal final class LazyReflection<R>: Reflection where R: Reflection {
    private let mirror: Mirror
    private var reflection: R?

    init(_ mirror: Mirror) throws {
        self.mirror = mirror
    }

    func reflect() throws -> R {
        try reflection ?? {
            reflection = try R(mirror)
            return reflection!
        }()
    }

    subscript<T>(dynamicMember keyPath: KeyPath<R, T>) -> T? {
        try? reflect()[keyPath: keyPath]
    }
}
