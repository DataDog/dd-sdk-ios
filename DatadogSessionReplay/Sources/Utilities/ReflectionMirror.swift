/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

internal protocol Reflection {
    init(_ mirror: ReflectionMirror) throws
}

extension Reflection {
    init(reflecting subject: Any) throws {
        let mirror = ReflectionMirror(reflecting: subject)
        try self.init(mirror)
    }
}

struct ReflectionMirror {
    /// An element of the reflected instance's structure.
    ///
    /// When the `label` component in not `nil`, it may represent the name of a
    /// stored property or an active `enum` case. If you pass strings to the
    /// `descendant(_:_:)` method, labels are used for lookup.
    typealias Child = (label: String?, value: Any)

    /// The type used to represent substructure.
    ///
    /// When working with a mirror that reflects a bidirectional or random access
    /// collection, you may find it useful to "upgrade" instances of this type
    /// to `AnyBidirectionalCollection` or `AnyRandomAccessCollection`. For
    /// example, to display the last twenty children of a mirror if they can be
    /// accessed efficiently, you write the following code:
    ///
    ///     if let b = AnyBidirectionalCollection(someMirror.children) {
    ///         for element in b.suffix(20) {
    ///             print(element)
    ///         }
    ///     }
    typealias Children = AnyCollection<Child>

    /// A suggestion of how a mirror's subject is to be interpreted.
    ///
    /// Playgrounds and the debugger will show a representation similar
    /// to the one used for instances of the kind indicated by the
    /// `DisplayStyle` case name when the mirror is used for display.
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

    enum Error: Swift.Error {
        struct Context {
            let subjectType: Any.Type
            let paths: [Path]
        }
        case notFound(Context)
        case typeMismatch(Context, expect: Any.Type, got: Any.Type)

    }

    final class Lazy<T> {
        lazy var `lazy`: T? = load()
        private let load: () -> T?

        init(_ load: @escaping () -> T?) {
            self.load = load
        }
    }

    let subject: Any

    /// The static type of the subject being reflected.
    ///
    /// This type may differ from the subject's dynamic type when this mirror
    /// is the `superclassMirror` of another mirror.
    let subjectType: Any.Type

    /// A suggested display style for the reflected subject.
    let displayStyle: DisplayStyle

    /// A collection of `Child` elements describing the structure of the
    /// reflected subject.
    let children: Children

    /// A mirror of the subject's superclass, if one exists.
    var superclassMirror: ReflectionMirror? { _superclassMirror.lazy }

    var keyPath: [String: Int]? { _keyPath.lazy }

    let parentPaths: [Path]

    private let _keyPath: Lazy<[String: Int]>
    private let _superclassMirror: Lazy<ReflectionMirror>

    private let telemetry: Telemetry

    init<C>(
        subject: Any,
        subjectType: Any.Type,
        displayStyle: DisplayStyle,
        children: C = [],
        keyPath: Lazy<[String: Int]> = nil,
        superclassMirror: Lazy<ReflectionMirror> = nil,
        parentPaths: [Path] = [],
        telemetry: Telemetry = NOPTelemetry()
    ) where C: Collection, C.Element == Child {
        self.subject = subject
        self.subjectType = subjectType
        self.displayStyle = displayStyle
        self.children = Children(children)
        self._keyPath = keyPath
        self._superclassMirror = superclassMirror
        self.parentPaths = parentPaths
        self.telemetry = telemetry
    }
}

extension ReflectionMirror {
    /// Creates a mirror that reflects on the given instance.
    ///
    /// - Parameter subject: The instance for which to create a mirror.
    init(
        reflecting subject: Any,
        subjectType: Any.Type? = nil,
        parentPaths: [Path] = [],
        telemetry: Telemetry = NOPTelemetry()
    ) {
        let subjectType = subjectType ?? _getNormalizedType(subject, type: type(of: subject))
        let metadataKind = _MetadataKind(subjectType)
        let childCount = _getChildCount(subject, type: subjectType)

        let children = (0 ..< childCount).lazy.map {
            _child(of: subject, type: subjectType, index: $0)
        }

        switch metadataKind {
        case .class, .objcClassWrapper:
            let recursiveChildCount = _getRecursiveChildCount(subjectType)
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .class,
                children: children,
                keyPath: Lazy {
                    _keyPaths(subjectType, count: childCount, recursiveCount: recursiveChildCount)
                },
                superclassMirror: Lazy {
                    _getSuperclass(subjectType).map {
                        ReflectionMirror(
                            reflecting: subject,
                            subjectType: $0,
                            parentPaths: parentPaths,
                            telemetry: telemetry
                        )
                    }
                },
                parentPaths: parentPaths,
                telemetry: telemetry
            )

        case .struct:
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .struct,
                children: children,
                keyPath: Lazy { _keyPaths(subjectType, count: childCount) },
                parentPaths: parentPaths,
                telemetry: telemetry
            )

        case .enum:
            let caseName = _getEnumCaseName(subject).map { String(cString: $0) } ?? ""
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .enum(case: caseName),
                children: children,
                parentPaths: parentPaths,
                telemetry: telemetry
            )

        case .tuple:
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .tuple,
                children: children,
                parentPaths: parentPaths,
                telemetry: telemetry
            )

        case .optional:
            if 0 < childCount {
                let some = _child(of: subject, type: subjectType, index: 0)
                self.init(
                    reflecting: some.value,
                    parentPaths: parentPaths,
                    telemetry: telemetry
                )
            } else {
                self.init(
                    subject: subject,
                    subjectType: subjectType,
                    displayStyle: .nil,
                    parentPaths: parentPaths,
                    telemetry: telemetry
                )
            }

        default:
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .unknown,
                parentPaths: parentPaths,
                telemetry: telemetry
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

        guard let value = descendant(paths: &paths) else {
            throw ReflectionMirror.Error.notFound(.init(subjectType: subjectType, paths: paths))
        }

        guard let value = value as? T else {
            throw ReflectionMirror.Error.typeMismatch(
                .init(subjectType: subjectType, paths: paths),
                expect: type,
                got: Swift.type(of: value)
            )
        }

        return value
    }

    func descendant<T>(type: T.Type = T.self, _ first: Path, _ rest: Path...) throws -> T where T: Reflection {
        var paths = [first] + rest

        guard let value = descendant(paths: &paths) else {
            throw ReflectionMirror.Error.notFound(.init(subjectType: subjectType, paths: paths))
        }

        return try T(reflecting: value)
    }

    private func descendant(paths: inout [Path]) -> Any? {
        let path = paths.removeFirst()

        guard let child = descendant(path: path) else {
            return nil
        }

        if paths.isEmpty {
            return child
        }

        return ReflectionMirror(
            reflecting: child,
            parentPaths: parentPaths + [path],
            telemetry: telemetry
        ).descendant(paths: &paths)
    }

    private func descendant(path: Path) -> Any? {
        if case let .index(index) = path, index < children.count {
            return children[AnyIndex(index)].value
        }

        if case let .key(key) = path, let index = keyPath?[key] {
            return children[AnyIndex(index)].value
        }

        return superclassMirror?.descendant(path: path)
    }
}

extension Array: Reflection where Element: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        guard let subject = mirror.subject as? Array<Any> else {
            throw ReflectionMirror.Error.typeMismatch(
                .init(subjectType: mirror.subjectType, paths: mirror.parentPaths),
                expect: Array<Any>.self,
                got: mirror.subjectType
            )
        }

        self = try subject.map { try Element(reflecting: $0) }
    }
}

extension Dictionary: Reflection where Key: Reflection, Value: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        guard let subject = mirror.subject as? Dictionary<AnyHashable, Any> else {
            throw ReflectionMirror.Error.typeMismatch(
                .init(subjectType: mirror.subjectType, paths: mirror.parentPaths),
                expect: Dictionary<AnyHashable, Any>.self,
                got: mirror.subjectType
            )
        }

        self = try subject.reduce(into: [:]) { result, element in
            try result[Key(reflecting: element.key.base)] = Value(reflecting: element.value)
        }
    }
}

extension Reflection {
    typealias Lazy = ReflectionMirror.Lazy<Self>
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

extension ReflectionMirror.Lazy: ExpressibleByNilLiteral {
    convenience init(nilLiteral: ()) {
        self.init({ nil })
    }
}

extension ReflectionMirror.Lazy: Reflection where T: Reflection {
    convenience init(_ mirror: ReflectionMirror) throws {
        self.init({ try? T(mirror) })
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

@_silgen_name("swift_EnumCaseName")
internal func _getEnumCaseName<T>(_ value: T) -> UnsafePointer<CChar>?

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

internal typealias NameFreeFunc = @convention(c) (UnsafePointer<CChar>?) -> Void

@_silgen_name("swift_reflectionMirror_subscript")
internal func _getChild<T>(
    of: T,
    type: Any.Type,
    index: Int,
    outName: UnsafeMutablePointer<UnsafePointer<CChar>?>,
    outFreeFunc: UnsafeMutablePointer<NameFreeFunc?>
) -> Any

private enum _MetadataKind: UInt {
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
        self = _MetadataKind(rawValue: rawValue) ?? .unknown
    }
}

private func _child<T>(of value: T, type: Any.Type, index: Int) -> (label: String?, value: Any) {
    var nameC: UnsafePointer<CChar>? = nil
    var freeFunc: NameFreeFunc? = nil
    let value = _getChild(of: value, type: type, index: index, outName: &nameC, outFreeFunc: &freeFunc)
    let name = nameC.flatMap { String(validatingUTF8: $0) }
    freeFunc?(nameC)
    return (name, value)
}

private func _keyPaths(_ type: Any.Type, count: Int, recursiveCount: Int) -> [String: Int] {
    let skip = recursiveCount - count
    return (skip..<recursiveCount).reduce(into: [:]) { result, index in
        var field = _FieldReflectionMetadata()
        _getChildMetadata(type, index: index, fieldMetadata: &field)
        defer { field.freeFunc?(field.name) }

        field.name
            .flatMap { String(cString: $0) }
            .map { result[$0] = index - skip }
    }
}

private func _keyPaths(_ type: Any.Type, count: Int) -> [String: Int] {
    _keyPaths(type, count: count, recursiveCount: count)
}
