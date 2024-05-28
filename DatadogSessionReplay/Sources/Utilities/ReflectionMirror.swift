/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

internal protocol Reflection_ {
    init(_ mirror: ReflectionMirror) throws
}

extension Reflection_ {
    init(reflecting_ subject: Any) throws {
        let mirror = ReflectionMirror(reflecting: subject)
        try self.init(mirror)
    }
}

struct ReflectionMirror {
    typealias Child = (label: String?, value: Any)

    typealias Children = AnyCollection<Child>

    enum DisplayStyle {
        case `struct`
        case `class`
        case `enum`(case: String)
        case tuple
        case `nil`
        case unknown
    }

    @frozen enum Path {
        case index(Int)
        case key(String)
    }

    final class Lazy<T> {
        lazy var `lazy`: T? = load()
        private let load: () -> T?

        init(_ load: @escaping () -> T?) {
            self.load = load
        }
    }

    let subject: Any
    let subjectType: Any.Type
    let displayStyle: DisplayStyle
    let children: Children
    var superclassMirror: ReflectionMirror? { _superclassMirror?.lazy }

    private let namedFields: [String: Int]
    private let _superclassMirror: Lazy<ReflectionMirror>?

    init<C>(
        subject: Any,
        subjectType: Any.Type,
        displayStyle: DisplayStyle,
        children: C = [],
        namedFields: [String: Int] = [:],
        superclassMirror: Lazy<ReflectionMirror>? = nil
    ) where C: Collection, C.Element == Child {
        self.subject = subject
        self.subjectType = subjectType
        self.displayStyle = displayStyle
        self.children = Children(children)
        self.namedFields = namedFields
        self._superclassMirror = superclassMirror
    }
}

extension ReflectionMirror {
    init(reflecting subject: Any, subjectType: Any.Type? = nil) {
        let subjectType = subjectType ?? _getNormalizedType(subject, type: type(of: subject))
        let metadataKind = MetadataKind(subjectType)
        let childCount = _getChildCount(subject, type: subjectType)

        let children = (0 ..< childCount).lazy.map {
            getChild(of: subject, type: subjectType, index: $0)
        }

        switch metadataKind {
        case .class, .objcClassWrapper:
            let recursiveChildCount = _getRecursiveChildCount(subjectType)
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .class,
                children: children,
                namedFields: _namedFields(subjectType, count: childCount, recursiveCount: recursiveChildCount),
                superclassMirror: Lazy {
                    _getSuperclass(subjectType).map { ReflectionMirror(reflecting: subject, subjectType: $0) }
                }
            )

        case .struct:
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .struct,
                children: children,
                namedFields: _namedFields(subjectType, count: childCount)
            )

        case .enum:
            let caseName = _getEnumCaseName(subject).map { String(cString: $0) } ?? ""
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .enum(case: caseName),
                children: children
            )

        case .tuple:
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .tuple,
                children: children
            )

        case .optional:
            if 0 < childCount {
                let some = getChild(of: subject, type: subjectType, index: 0)
                self.init(reflecting: some.value)
            } else {
                self.init(
                    subject: subject,
                    subjectType: subjectType,
                    displayStyle: .nil
                )
            }

        default:
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .unknown
            )
        }
    }
}

extension ReflectionMirror {
    /// Returns a specific descendant of the reflected subject, or `nil` if no
    /// such descendant exists.
    ///
    /// Pass a variadic list of string and integer arguments. Each string
    /// argument selects the first child with a matching label. Each integer
    /// argument selects the child at that offset. For example, passing
    /// `1, "two", 3` as arguments to `myMirror.descendant(_:_:)` is equivalent
    /// to:
    ///
    ///     var result: Any? = nil
    ///     let children = myMirror.children
    ///     if let i0 = children.index(
    ///         children.startIndex, offsetBy: 1, limitedBy: children.endIndex),
    ///         i0 != children.endIndex
    ///     {
    ///         let grandChildren = Mirror(reflecting: children[i0].value).children
    ///         if let i1 = grandChildren.firstIndex(where: { $0.label == "two" }) {
    ///             let greatGrandChildren =
    ///                 Mirror(reflecting: grandChildren[i1].value).children
    ///             if let i2 = greatGrandChildren.index(
    ///                 greatGrandChildren.startIndex,
    ///                 offsetBy: 3,
    ///                 limitedBy: greatGrandChildren.endIndex),
    ///                 i2 != greatGrandChildren.endIndex
    ///             {
    ///                 // Success!
    ///                 result = greatGrandChildren[i2].value
    ///             }
    ///         }
    ///     }
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
    ///   - first: The first mirror path component to access.
    ///   - rest: Any remaining mirror path components.
    /// - Returns: The descendant of this mirror specified by the given mirror
    ///   path components if such a descendant exists; otherwise, `nil`.
    func descendant(_ first: Path, _ rest: Path...) -> Any? {
        var paths = [first] + rest
        return descendant(paths: &paths)
    }

    func descendant<T>(type: T.Type = T.self, _ first: Path, _ rest: Path...) throws -> T {
        var paths = [first] + rest

        guard let value = descendant(paths: &paths) as? T else {
            throw InternalError(description: "property \(first) type mismatch")
        }

        return value
    }

    func descendant<T>(type: T.Type = T.self, _ first: Path, _ rest: Path...) throws -> T where T: Reflection_ {
        var paths = [first] + rest

        guard let value = descendant(paths: &paths) else {
            throw InternalError(description: "property at path \(paths) not found")
        }

        return try T(reflecting_: value)
    }

    private func descendant(paths: inout [Path]) -> Any? {
        let path = paths.removeFirst()

        guard let child = descendant(path: path) else {
            return nil
        }

        if paths.isEmpty {
            return child
        }

        return ReflectionMirror(reflecting: child).descendant(paths: &paths)
    }

    private func descendant(path: Path) -> Any? {
        if case let .index(index) = path, index < children.count {
            return children[AnyIndex(index)].value
        }

        if case let .key(key) = path, let index = namedFields[key] {
            return children[AnyIndex(index)].value
        }

        return superclassMirror?.descendant(path: path)
    }
}

extension Array: Reflection_ where Element: Reflection_ {
    init(_ mirror: ReflectionMirror) throws {
        guard let subject = mirror.subject as? Array<Any> else {
            throw InternalError(description: "type mismatch: not a collection")
        }

        self = try subject.map { try Element(reflecting_: $0) }
    }
}

extension Dictionary: Reflection_ where Key: Reflection_, Value: Reflection_ {
    init(_ mirror: ReflectionMirror) throws {
        guard let subject = mirror.subject as? Dictionary<AnyHashable, Any> else {
            throw InternalError(description: "type mismatch: not a key:value pair")
        }

        self = try subject.reduce(into: [:]) { result, element in
            try result[Key(reflecting_: element.key.base)] = Value(reflecting_: element.value)
        }
    }
}

extension Reflection_ {
    typealias Lazy_ = ReflectionMirror.Lazy<Self>
}

extension ReflectionMirror.Path: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) {
        self = .index(value)
    }
}

extension ReflectionMirror.Path: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .key(value)
    }
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftShims

// Returns 'c' (class), 'e' (enum), 's' (struct), 't' (tuple), or '\0' (none)
@_silgen_name("swift_reflectionMirror_displayStyle")
internal func _getDisplayStyle<T>(_: T) -> CChar

@_silgen_name("swift_EnumCaseName")
func _getEnumCaseName<T>(_ value: T) -> UnsafePointer<CChar>?

@_silgen_name("swift_getMetadataKind")
internal func _metadataKind(_: Any.Type) -> UInt

@_silgen_name("swift_reflectionMirror_normalizedType")
internal func _getNormalizedType<T>(_: T, type: Any.Type) -> Any.Type

@_silgen_name("swift_reflectionMirror_count")
internal func _getChildCount<T>(_: T, type: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveCount")
internal func _getRecursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
internal func _getChildMetadata(
    _: Any.Type,
    index: Int,
    fieldMetadata: UnsafeMutablePointer<_FieldReflectionMetadata>
) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
internal func _getChildOffset(
    _: Any.Type,
    index: Int
) -> Int

internal typealias NameFreeFunc = @convention(c) (UnsafePointer<CChar>?) -> Void

@_silgen_name("swift_reflectionMirror_subscript")
internal func _getChild<T>(
    of: T,
    type: Any.Type,
    index: Int,
    outName: UnsafeMutablePointer<UnsafePointer<CChar>?>,
    outFreeFunc: UnsafeMutablePointer<NameFreeFunc?>
) -> Any

private enum MetadataKind: UInt {
    // With "flags":
    // runtimePrivate = 0x100
    // nonHeap = 0x200
    // nonType = 0x400

    case `class` = 0
    case `struct` = 0x200     // 0 | nonHeap
    case `enum` = 0x201       // 1 | nonHeap
    case optional = 0x202     // 2 | nonHeap
    case foreignClass = 0x203 // 3 | nonHeap
    case opaque = 0x300       // 0 | runtimePrivate | nonHeap
    case tuple = 0x301        // 1 | runtimePrivate | nonHeap
    case function = 0x302     // 2 | runtimePrivate | nonHeap
    case existential = 0x303  // 3 | runtimePrivate | nonHeap
    case metatype = 0x304     // 4 | runtimePrivate | nonHeap
    case objcClassWrapper = 0x305     // 5 | runtimePrivate | nonHeap
    case existentialMetatype = 0x306  // 6 | runtimePrivate | nonHeap
    case heapLocalVariable = 0x400    // 0 | nonType
    case heapGenericLocalVariable = 0x500 // 0 | nonType | runtimePrivate
    case errorObject = 0x501  // 1 | nonType | runtimePrivate
    case unknown = 0xffff

    init(_ type: Any.Type) {
        let rawValue = _metadataKind(type)
        self = MetadataKind(rawValue: rawValue) ?? .unknown
    }
}

private func getChild<T>(of value: T, type: Any.Type, index: Int) -> (label: String?, value: Any) {
    var nameC: UnsafePointer<CChar>? = nil
    var freeFunc: NameFreeFunc? = nil
    let value = _getChild(of: value, type: type, index: index, outName: &nameC, outFreeFunc: &freeFunc)
    let name = nameC.flatMap { String(validatingUTF8: $0) }
    freeFunc?(nameC)
    return (name, value)
}

private func _namedFields(_ type: Any.Type, count: Int, recursiveCount: Int) -> [String: Int] {
    let skip = recursiveCount - count
    return (skip..<recursiveCount).reduce(into: [:]) { result, index in
        var field = _FieldReflectionMetadata()
        _getChildMetadata(type, index: index, fieldMetadata: &field)
        defer { field.freeFunc?(field.name) }

        field.name
            .flatMap { String(validatingUTF8: $0) }
            .map { result[$0] = index - skip }
    }
}

private func _namedFields(_ type: Any.Type, count: Int) -> [String: Int] {
    _namedFields(type, count: count, recursiveCount: count)
}
