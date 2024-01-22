/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol StandardReflection {
    init(_ mirror: Mirror) throws
}

extension StandardReflection {
    init(std_reflecting subject: Any) throws {
        let mirror = Mirror(reflecting: subject)
        try self.init(mirror)
    }
}

extension Array: StandardReflection where Element: StandardReflection {
    init(_ mirror: Mirror) throws {
        guard mirror.displayStyle == .collection else {
            throw InternalError(description: "type mismatch: not a collection")
        }

        self = try mirror.children.map { try Element(std_reflecting: $0.value) }
    }
}

extension Dictionary: StandardReflection where Key: StandardReflection, Value: StandardReflection {
    init(_ mirror: Mirror) throws {
        guard mirror.displayStyle == .dictionary else {
            throw InternalError(description: "type mismatch: not a dictionary")
        }

        self = try mirror.children.reduce(into: [:]) { result, child in
            guard let pair = child.value as? (Any, Any) else {
                throw InternalError(description: "type mismatch: not a key:value pair")
            }

            try result[Key(std_reflecting: pair.0)] = Value(std_reflecting: pair.1)
        }
    }
}

extension Mirror {
    //swiftlint:disable:next function_default_parameter_at_end
    func descendant<Value>(_ type: Value.Type = Value.self, path: MirrorPath) throws -> Value {
        let child = try descendant(path) ?? superclassMirror?.descendant(type, path: path) as Any
        guard let value = child as? Value else {
            throw InternalError(description: "type mismatch at \(path)")
        }
        return value
    }

    //swiftlint:disable:next function_default_parameter_at_end
    func descendant<Value>(_ type: Value.Type = Value.self, path: MirrorPath) throws -> Value where Value: StandardReflection {
        let child = try descendant(path) ?? superclassMirror?.descendant(type, path: path) as? Any

        guard let child = child else {
            throw InternalError(description: "not found at \(path)")
        }

        let mirror = Mirror(reflecting: child)

        if mirror.displayStyle == .optional {
            return try mirror.descendant(Value.self, path: "some")
        }

        return try Value(mirror)
    }
}

extension StandardReflection {
    typealias Lazy = ReflectionMirror.Lazy<Self>
}
