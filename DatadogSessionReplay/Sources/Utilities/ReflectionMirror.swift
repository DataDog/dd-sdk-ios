/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A representation of the substructure and display style of an instance of
/// any type.
///
/// The `ReflectionMirror` defers from the standard ``Mirror`` in some key
/// aspect of its implementation:
///
/// ## Display style
/// The display styles are based on the type metadata and does not define additional
/// `optional`, `collection`, `dictionary`, or `set` which are set by
/// ``CustomReflectable`` implementation is standard mirroring.
///
/// Additionally, the `.enum` style will include the case name as associated value.
///
/// ## Optional type
/// If the subject type is optional, the display style will either be `nil` or represent the
/// wrapped subject type. If the subject is not `nil`, reflection will be applied to the wrapped
/// value instead of the subject itself.
///
/// ## Lazy inspection
/// All inspection endpoints are lazily loading child value, even when accessing property by key (this
/// is not the case with the standard `Mirror`). This is made possible by only loading the
/// fields metadata but not their values.
///
/// The `superclassMirror` is also lazily loaded, again this is not the case with the
/// standard `Mirror`.
///
/// ## Ignore custom reflection
/// The `ReflectionMirror` ignores the ``CustomReflectable`` or ``CustomLeafReflectable``
/// protocols and treat any conforming objects as `Any.Type`.
///
internal struct ReflectionMirror {
    /// An element of the reflected instance's structure.
    ///
    /// When the `label` component in not `nil`, it may represent the name of a
    /// stored property or an active `enum` case.
    typealias Child = (label: String?, value: Any)

    /// The type used to represent substructure.
    typealias Children = AnyCollection<Child>

    /// A suggestion of how a mirror's subject is to be interpreted.
    enum DisplayStyle: Equatable {
        case `struct`
        case `class`
        case `enum`(case: String)
        case tuple
        case `nil`
        case opaque
    }

    enum Path {
        case index(Int)
        case key(String)
    }

    private final class LazyBox<T> {
        lazy var `lazy`: T = load()
        private let load: () -> T

        init(_ load: @escaping () -> T) {
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

    var keyPaths: [String: Int]? { _keyPaths.lazy }

    private let _superclassMirror: LazyBox<ReflectionMirror?>
    private let _keyPaths: LazyBox<[String: Int]?>

    init<C>(
        subject: Any,
        subjectType: Any.Type,
        displayStyle: DisplayStyle,
        children: C = [],
        keyPaths: @autoclosure @escaping () -> [String: Int]? = nil,
        superclassMirror: @autoclosure @escaping () -> ReflectionMirror? = nil
    ) where C: Collection, C.Element == Child {
        self.subject = subject
        self.subjectType = subjectType
        self.displayStyle = displayStyle
        self.children = Children(children)
        self._keyPaths = LazyBox(keyPaths)
        self._superclassMirror = LazyBox(superclassMirror)
    }
}

extension ReflectionMirror {
    /// Creates a mirror that reflects on the given instance.
    ///
    /// - Parameter subject: The instance for which to create a mirror.
    init(
        reflecting subject: Any,
        subjectType: Any.Type? = nil
    ) {
        let subjectType = subjectType ?? _getNormalizedType(subject, type: type(of: subject))
        let metadataKind = _MetadataKind(subjectType)

        // All reflection implementation can be found at
        // https://github.com/apple/swift/blob/main/stdlib/public/runtime/ReflectionMirror.cpp
        switch metadataKind {
        case .class, .foreignClass, .objcClassWrapper:
            let childCount = _getChildCount(subject, type: subjectType)

            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .class,
                children: _getChildren(of: subject, type: subjectType, count: childCount),
                keyPaths: _getKeyPaths(
                    subjectType,
                    count: childCount,
                    recursiveCount: _getRecursiveChildCount(subjectType)
                ),
                superclassMirror: _getSuperclass(subjectType).map {
                    ReflectionMirror(
                        reflecting: subject,
                        subjectType: $0
                    )
                }
            )

        case .struct:
            let childCount = _getChildCount(subject, type: subjectType)
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .struct,
                children: _getChildren(of: subject, type: subjectType, count: childCount),
                keyPaths: _getKeyPaths(subjectType, count: childCount)
            )

        case .enum:
            let childCount = _getChildCount(subject, type: subjectType)
            let caseName = _getEnumCaseName(subject).map { String(cString: $0) } ?? ""
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .enum(case: caseName),
                children: _getChildren(of: subject, type: subjectType, count: childCount)
            )

        case .tuple:
            let childCount = _getChildCount(subject, type: subjectType)
            self.init(
                subject: subject,
                subjectType: subjectType,
                displayStyle: .tuple,
                children: _getChildren(of: subject, type: subjectType, count: childCount)
            )

        case .optional:
            // unwrap the optional by reflecting first child
            if 0 < _getChildCount(subject, type: subjectType) {
                let some = _getChild(of: subject, type: subjectType, index: 0)
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
                displayStyle: .opaque
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

    func descendant(_ paths: [Path]) -> Any? {
        var paths = paths
        return descendant(paths: &paths)
    }

    private func descendant(paths: inout [Path]) -> Any? {
        let path = paths.removeFirst()

        guard let child = descendant(path: path) else {
            return nil
        }

        if paths.isEmpty {
            return child
        }

        return ReflectionMirror(reflecting: child)
            .descendant(paths: &paths)
    }

    private func descendant(path: Path) -> Any? {
        if case let .index(index) = path, index < children.count {
            return children[AnyIndex(index)].value
        }

        if case let .key(key) = path, let index = keyPaths?[key] {
            return children[AnyIndex(index)].value
        }

        return superclassMirror?.descendant(path: path)
    }
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

private func _getChild<T>(of value: T, type: Any.Type, index: Int) -> ReflectionMirror.Child {
    var nameC: UnsafePointer<CChar>? = nil
    var freeFunc: NameFreeFunc? = nil
    let value = _getChild(of: value, type: type, index: index, outName: &nameC, outFreeFunc: &freeFunc)
    let name = nameC.flatMap { String(cString: $0) }
    freeFunc?(nameC)
    return (name, value)
}

private func _getChildren<T>(of value: T, type: Any.Type, count: Int) -> any Collection<ReflectionMirror.Child> {
    (0 ..< count).lazy.map {
        _getChild(of: value, type: type, index: $0)
    }
}

/// Gets indexes of non-recursive named fields of a reference type.
///
/// This functions uses the `swift_reflectionMirror_recursiveChildMetadata` API as there
/// is no non-recursive counterpart. To read fields' metadata of the given type in a non-recursive way, it needs to skip
/// indexes of its parent's fields by substracting the non-recursive child count to the recursive child count.
///
/// For inherating types, the recursive children include the parent types' children.
///
/// - Parameters:
///   - type: The type to inspect.
///   - count: The child count from `swift_reflectionMirror_count`.
///   - recursiveCount: The child count from `swift_reflectionMirror_recursiveCount`.
/// - Returns: The key paths as a dictionary of indexes associted to a key.
private func _getKeyPaths(_ type: Any.Type, count: Int, recursiveCount: Int) -> [String: Int] {
    let skip = recursiveCount - count
    return (skip..<recursiveCount).reduce(into: [:]) { result, index in
        var field = _FieldReflectionMetadata()
        _ = _getChildMetadata(type, index: index, fieldMetadata: &field)

        field.name
            .flatMap { String(cString: $0) }
            .map { result[$0] = index - skip }

        field.freeFunc?(field.name)
    }
}

/// Gets indexes of named fields of value type.
///
/// - Parameters:
///   - type: The type to inspect.
///   - count: The child count from `swift_reflectionMirror_count`.
/// - Returns: The key paths as a dictionary of indexes associted to a key.
private func _getKeyPaths(_ type: Any.Type, count: Int) -> [String: Int] {
    _getKeyPaths(type, count: count, recursiveCount: count)
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
private func _getEnumCaseName<T>(_ value: T) -> UnsafePointer<CChar>?

@_silgen_name("swift_getMetadataKind")
private func _metadataKind(_: Any.Type) -> UInt

@_silgen_name("swift_reflectionMirror_normalizedType")
private func _getNormalizedType<T>(_: T, type: Any.Type) -> Any.Type

@_silgen_name("swift_reflectionMirror_count")
private func _getChildCount<T>(_: T, type: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveCount")
private func _getRecursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func _getChildMetadata(
    _: Any.Type,
    index: Int,
    fieldMetadata: UnsafeMutablePointer<_FieldReflectionMetadata>
) -> Any.Type

private typealias NameFreeFunc = @convention(c) (UnsafePointer<CChar>?) -> Void

@_silgen_name("swift_reflectionMirror_subscript")
private func _getChild<T>(
    of: T,
    type: Any.Type,
    index: Int,
    outName: UnsafeMutablePointer<UnsafePointer<CChar>?>,
    outFreeFunc: UnsafeMutablePointer<NameFreeFunc?>
) -> Any

// https://github.com/apple/swift/blob/main/include/swift/ABI/MetadataKind.def
private enum _MetadataKind: UInt {
    // With "flags":
    // runtimePrivate = 0x100
    // nonHeap = 0x200
    // nonType = 0x400

    case `class` = 0
    case `struct` = 0x200                   // 0 | nonHeap
    case `enum` = 0x201                     // 1 | nonHeap
    case optional = 0x202                   // 2 | nonHeap
    case foreignClass = 0x203               // 3 | nonHeap
    case foreignReferenceType = 0x204       // 4 | nonHeap
    case opaque = 0x300                     // 0 | runtimePrivate | nonHeap
    case tuple = 0x301                      // 1 | runtimePrivate | nonHeap
    case function = 0x302                   // 2 | runtimePrivate | nonHeap
    case existential = 0x303                // 3 | runtimePrivate | nonHeap
    case metatype = 0x304                   // 4 | runtimePrivate | nonHeap
    case objcClassWrapper = 0x305           // 5 | runtimePrivate | nonHeap
    case existentialMetatype = 0x306        // 6 | runtimePrivate | nonHeap
    case extendedExistential = 0x307        // 7 | runtimePrivate | nonHeap
    case heapLocalVariable = 0x400          // 0 | nonType
    case heapGenericLocalVariable = 0x500   // 0 | nonType | runtimePrivate
    case errorObject = 0x501                // 1 | nonType | runtimePrivate
    case task = 0x502                       // 2 | nonType | runtimePrivate
    case job = 0x503                        // 3 | nonType | runtimePrivate
    /// The largest possible non-isa-pointer metadata kind value.
    ///
    /// This is included in the enumeration to prevent against attempts to
    /// exhaustively match metadata kinds. Future Swift runtimes or compilers
    /// may introduce new metadata kinds, so for forward compatibility, the
    /// runtime must tolerate metadata with unknown kinds.
    /// This specific value is not mapped to a valid metadata kind at this time,
    /// however.
    case unknown = 0x7FF

    init(_ type: Any.Type) {
        let rawValue = _metadataKind(type)
        self = _MetadataKind(rawValue: rawValue) ?? .unknown
    }
}
