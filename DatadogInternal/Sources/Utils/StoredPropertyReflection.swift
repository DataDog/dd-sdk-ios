/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftShims

/// Reads a stored descendant without materializing the structs containing it.
internal enum StoredPropertyReflection {
    enum Error: Swift.Error {
        case unsupportedLayout
    }

    static func descendant(of mirror: ReflectionMirror, at paths: [ReflectionMirror.Path]) throws -> Any? {
        guard !paths.isEmpty else {
            return nil
        }
        guard MetadataKind(rawValue: _metadataKind(mirror.subjectType)) == .class else {
            throw Error.unsupportedLayout
        }

        let owner = mirror.subject as AnyObject
        return try withExtendedLifetime(owner) {
            var address = UnsafeRawPointer(Unmanaged.passUnretained(owner).toOpaque())
            var parentType = mirror.subjectType

            for (position, path) in paths.enumerated() {
                guard case let .key(name) = path else {
                    throw Error.unsupportedLayout
                }
                guard let field = try storedField(named: name, in: parentType) else {
                    return nil
                }

                if position == paths.count - 1 {
                    let value: Any
                    if position == 0 {
                        // A direct class field has no intermediate struct to copy.
                        guard let directValue = mirror.descendant(paths) else {
                            return nil
                        }
                        value = directValue
                    } else {
                        value = child(at: address, parentType: parentType, index: field.index)
                    }
                    // Swift reflection substitutes Void for fields it cannot copy.
                    guard !(value is Void) || field.type == Void.self
                        || MetadataKind(rawValue: _metadataKind(field.type)) == .existential else {
                        throw Error.unsupportedLayout
                    }
                    return value
                }

                guard MetadataKind(rawValue: _metadataKind(field.type)) == .struct else {
                    throw Error.unsupportedLayout
                }
                address = address.advanced(by: field.offset)
                parentType = field.type
            }
            return nil
        }
    }

    private struct StoredField {
        let index: Int
        let offset: Int
        let type: Any.Type
    }

    private static func storedField(named name: String, in type: Any.Type) throws -> StoredField? {
        // Inherited fields precede the most derived class's fields.
        for index in (0..<_getRecursiveChildCount(type)).reversed() {
            var field = _FieldReflectionMetadata()
            let fieldType = _getChildMetadata(type, index: index, fieldMetadata: &field)
            defer { field.freeFunc?(field.name) }

            guard field.name.map({ String(cString: $0) }) == name else {
                continue
            }
            guard field.isStrong else {
                throw Error.unsupportedLayout
            }
            let offset = _getChildOffset(type, index: index)
            guard offset >= 0 else {
                throw Error.unsupportedLayout
            }
            return StoredField(index: index, offset: offset, type: fieldType)
        }
        return nil
    }

    private static func child(at address: UnsafeRawPointer, parentType: Any.Type, index: Int) -> Any {
        func open<Parent>(_ type: Parent.Type) -> Any {
            borrowedChild(at: address, parent: type, parentType: parentType, index: index)
        }
        return _openExistential(parentType, do: open)
    }

    private static func borrowedChild<Parent: ~Copyable>(
        at address: UnsafeRawPointer,
        parent: Parent.Type,
        parentType: Any.Type,
        index: Int
    ) -> Any {
        var name: UnsafePointer<CChar>?
        var free: NameFreeFunc?
        defer { free?(name) }
        // Suppressing Copyable is essential: a Copyable generic parent can be
        // copied into temporary storage even when the callee borrows it.
        return _getChild(
            of: address.assumingMemoryBound(to: Parent.self).pointee,
            type: parentType,
            index: index,
            outName: &name,
            outFreeFunc: &free
        )
    }
}

private enum MetadataKind: UInt {
    case `class` = 0
    case `struct` = 0x200
    case existential = 0x303
}

// Metadata lookup follows Swift's field enumeration implementation:
// https://github.com/swiftlang/swift/blob/33ed3118bb034651a01d874eb6a61918b82c6df8/stdlib/public/core/ReflectionMirror.swift
// The subscript entry point retains its generic Swift calling convention and
// delegates leaf copying to the runtime, including special field representations.

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

@_silgen_name("swift_getMetadataKind")
private func _metadataKind(_: Any.Type) -> UInt

@_silgen_name("swift_reflectionMirror_recursiveCount")
private func _getRecursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func _getChildMetadata(
    _: Any.Type,
    index: Int,
    fieldMetadata: UnsafeMutablePointer<_FieldReflectionMetadata>
) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
private func _getChildOffset(_: Any.Type, index: Int) -> Int

private typealias NameFreeFunc = @convention(c) (UnsafePointer<CChar>?) -> Void

@_silgen_name("swift_reflectionMirror_subscript")
private func _getChild<T: ~Copyable>(
    of: borrowing T,
    type: Any.Type,
    index: Int,
    outName: UnsafeMutablePointer<UnsafePointer<CChar>?>,
    outFreeFunc: UnsafeMutablePointer<NameFreeFunc?>
) -> Any
