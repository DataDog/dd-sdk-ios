/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Manages stack of nested types for their transformation.
internal class TransformationContext<T> {
    private var stack: [T] = []

    func enter(_ type: T) {
        stack.append(type)
    }

    func leave() {
        stack = stack.dropLast()
    }

    var current: T? { stack.last }
    var parent: T? { stack.dropLast().last }

    func predecessor(matching predicate: (T) -> Bool) -> T? {
        return stack.reversed().first { predicate($0) }
    }
}

/// Transforms given type `T`.
internal class TypeTransformer<T> {
    let context = TransformationContext<T>()

    func transform(types: [T]) throws -> [T] {
        assertionFailure("Must be implemetned by subclasses.")
        return types
    }
}
