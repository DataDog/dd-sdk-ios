/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * https://github.com/pointfreeco/swift-custom-dump
 *
 * MIT License
 *
 * Copyright (c) 2021 Point-Free, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#if DEBUG

// swiftlint:disable function_default_parameter_at_end

import Foundation

/// Dumps the given value's contents using its mirror to standard output.
///
/// This function aims to dump the contents of a value into a nicely formatted, tree-like
/// description. It works with any value passed to it.
///
/// - Parameters:
///   - value: The value to output to the `target` stream.
///   - name: A label to use when writing the contents of `value`. When `nil` is passed, the label
///     is omitted. The default is `nil`.
///   - indent: The number of spaces to use as an indent for each line of the output. The default is
///     `0`.
///   - maxDepth: The maximum depth to descend when writing the contents of a value that has nested
///     components. The default is `Int.max`.
/// - Returns: The instance passed as `value`.
@discardableResult
internal func customDump<T>(
    _ value: T,
    name: String? = nil,
    indent: Int = 0,
    maxDepth: Int = .max
) -> T {
    var target = ""
    let value = customDump(value, to: &target, name: name, indent: indent, maxDepth: maxDepth)
    print(target)
    return value
}

internal struct ObjectTracker {
    var idPerItem: [ObjectIdentifier: UInt] = [:]
    var occurrencePerType: [String: UInt] = [:]
    var visitedItems: Set<ObjectIdentifier> = []
}

/// Dumps the given value's contents using its mirror to the specified output stream.
///
/// - Parameters:
///   - value: The value to output to the `target` stream.
///   - target: The stream to use for writing the contents of `value`.
///   - name: A label to use when writing the contents of `value`. When `nil` is passed, the label
///     is omitted. The default is `nil`.
///   - indent: The number of spaces to use as an indent for each line of the output. The default is
///     `0`.
///   - maxDepth: The maximum depth to descend when writing the contents of a value that has nested
///     components. The default is `Int.max`.
/// - Returns: The instance passed as `value`.
@discardableResult
public func customDump<T, TargetStream>(
    _ value: T,
    to target: inout TargetStream,
    name: String? = nil,
    indent: Int = 0,
    maxDepth: Int = .max
) -> T where TargetStream: TextOutputStream {
    var tracker = ObjectTracker()
    return _customDump(
        value,
        to: &target,
        name: name,
        indent: indent,
        isRoot: true,
        maxDepth: maxDepth,
        tracker: &tracker
    )
}

@discardableResult
private func _customDump<T, TargetStream>(
    _ value: T,
    to target: inout TargetStream,
    name: String?,
    nameSuffix: String = ":",
    indent: Int,
    isRoot: Bool,
    maxDepth: Int,
    tracker: inout ObjectTracker
) -> T where TargetStream: TextOutputStream {
    func customDumpHelp<InnerT, InnerTargetStream>(
        _ value: InnerT,
        to target: inout InnerTargetStream,
        name: String?,
        nameSuffix: String,
        indent: Int,
        isRoot: Bool,
        maxDepth: Int
    ) where InnerTargetStream: TextOutputStream {
        if InnerT.self is AnyObject.Type, withUnsafeBytes(of: value, { $0.allSatisfy { $0 == 0 } }) {
            target.write(
                (name.map { "\($0)\(nameSuffix) " } ?? "")
                    .appending("(null pointer)")
                    .indenting(by: indent)
            )
            return
        }

        let mirror = Mirror(reflecting: value)
        var out = ""

        func dumpChildren(
            of mirror: Mirror,
            prefix: String,
            suffix: String,
            shouldSort: Bool,
            filter isIncluded: (Mirror.Child) -> Bool = { _ in true },
            by areInIncreasingOrder: (Mirror.Child, Mirror.Child) -> Bool = { _, _ in false },
            map transform: (inout Mirror.Child, Int) -> Void = { _, _ in }
        ) {
            out.write(prefix)
            if let superclassMirror = mirror.superclassMirror {
                dumpChildren(
                    of: superclassMirror,
                    prefix: prefix,
                    suffix: suffix,
                    shouldSort: shouldSort,
                    filter: isIncluded,
                    by: areInIncreasingOrder,
                    map: transform
                )
            }
            if !mirror.children.isEmpty {
                if mirror.isSingleValueContainer {
                    var childOut = ""
                    let child = mirror.children.first! //swiftlint:disable:this force_unwrapping
                    customDumpHelp(
                        child.value,
                        to: &childOut,
                        name: child.label,
                        nameSuffix: ":",
                        indent: 0,
                        isRoot: false,
                        maxDepth: maxDepth - 1
                    )
                    if childOut.contains("\n") {
                        if maxDepth <= 0 {
                            out.write("…")
                        } else {
                            out.write("\n")
                            out.write(childOut.indenting(by: 2))
                            out.write("\n")
                        }
                    } else {
                        out.write(childOut)
                    }
                } else if maxDepth <= 0 {
                    out.write("…")
                } else {
                    out.write("\n")
                    var children = Array(mirror.children)
                    children.removeAll(where: { !isIncluded($0) })
                    if shouldSort {
                        children.sort(by: areInIncreasingOrder)
                    }
                    for (offset, var child) in children.enumerated() {
                        transform(&child, offset)
                        customDumpHelp(
                            child.value,
                            to: &out,
                            name: child.label,
                            nameSuffix: ":",
                            indent: 2,
                            isRoot: false,
                            maxDepth: maxDepth - 1
                        )
                        if offset != children.count - 1 {
                            out.write(",")
                        }
                        out.write("\n")
                    }
                }
            }
            out.write(suffix)
        }

        switch (value, mirror.displayStyle) {
        case let (value as Any.Type, _):
            out.write("\(_typeName(value)).self")

        case let (value as AnyObject, .class?):
            let item = ObjectIdentifier(value)
            var occurrence = tracker.occurrencePerType[_typeName(mirror.subjectType), default: 0] {
                didSet { tracker.occurrencePerType[_typeName(mirror.subjectType)] = occurrence }
            }

            var id: String {
                let id = tracker.idPerItem[item, default: occurrence]
                tracker.idPerItem[item] = id

                return id > 0 ? "#\(id)" : ""
            }
            if !id.isEmpty {
                out.write("\(id) ")
            }
            if tracker.visitedItems.contains(item) {
                out.write("\(_typeName(mirror.subjectType))(↩︎)")
            } else {
                tracker.visitedItems.insert(item)
                occurrence += 1
                var children = Array(mirror.children)

                var superclassMirror = mirror.superclassMirror
                while let mirror = superclassMirror {
                    children.insert(contentsOf: mirror.children, at: 0)
                    superclassMirror = mirror.superclassMirror
                }
                dumpChildren(
                    of: Mirror(value, children: children),
                    prefix: "\(_typeName(mirror.subjectType))(",
                    suffix: ")",
                    shouldSort: false,
                    filter: macroPropertyFilter(for: value)
                )
            }

        case (_, .collection?):
            dumpChildren(
                of: mirror,
                prefix: "[",
                suffix: "]",
                shouldSort: false,
                map: {
                    $0.label = "[\($1)]"
                }
            )

        case (_, .dictionary?):
            if mirror.children.isEmpty {
                out.write("[:]")
            } else {
                dumpChildren(
                    of: mirror,
                    prefix: "[",
                    suffix: "]",
                    shouldSort: mirror.subjectType is _UnorderedCollection.Type,
                    by: {
                        guard
                            let (lhsKey, _) = $0.value as? (key: AnyHashable, value: Any),
                            let (rhsKey, _) = $1.value as? (key: AnyHashable, value: Any)
                        else { return false }

                        let lhsDump = _customDump(
                            lhsKey.base,
                            name: nil,
                            indent: 0,
                            isRoot: false,
                            maxDepth: 1,
                            tracker: &tracker
                        )
                        let rhsDump = _customDump(
                            rhsKey.base,
                            name: nil,
                            indent: 0,
                            isRoot: false,
                            maxDepth: 1,
                            tracker: &tracker
                        )
                        return lhsDump < rhsDump
                    },
                    map: { child, _ in
                        guard let pair = child.value as? (key: AnyHashable, value: Any) else {
                            return
                        }
                        let key = _customDump(
                            pair.key.base,
                            name: nil,
                            indent: 0,
                            isRoot: false,
                            maxDepth: maxDepth - 1,
                            tracker: &tracker
                        )
                        child = (key, pair.value)
                    }
                )
            }

        case (_, .enum?):
            out.write(isRoot ? "\(_typeName(mirror.subjectType))." : ".")
            if let child = mirror.children.first {
                let childMirror = Mirror(reflecting: child.value)
                let associatedValuesMirror =
                childMirror.displayStyle == .tuple
                ? childMirror
                : Mirror(value, unlabeledChildren: [child.value], displayStyle: .tuple)
                dumpChildren(
                    of: associatedValuesMirror,
                    prefix: "\(child.label ?? "@unknown")(",
                    suffix: ")",
                    shouldSort: false,
                    map: { child, _ in
                        if child.label?.first == "." {
                            child.label = nil
                        }
                    }
                )
            } else {
                out.write("\(value)")
            }

        case (_, .optional?):
            if let value = mirror.children.first?.value {
                customDumpHelp(
                    value,
                    to: &out,
                    name: nil,
                    nameSuffix: "",
                    indent: 0,
                    isRoot: false,
                    maxDepth: maxDepth
                )
            } else {
                out.write("nil")
            }

        case (_, .set?):
            dumpChildren(
                of: mirror,
                prefix: "Set([",
                suffix: "])",
                shouldSort: mirror.subjectType is _UnorderedCollection.Type,
                by: {
                    let lhs = _customDump(
                        $0.value,
                        name: nil,
                        indent: 0,
                        isRoot: false,
                        maxDepth: 1,
                        tracker: &tracker
                    )
                    let rhs = _customDump(
                        $1.value,
                        name: nil,
                        indent: 0,
                        isRoot: false,
                        maxDepth: 1,
                        tracker: &tracker
                    )
                    return lhs < rhs
                }
            )

        case (_, .struct?):
            dumpChildren(
                of: mirror,
                prefix: "\(_typeName(mirror.subjectType))(",
                suffix: ")",
                shouldSort: false,
                filter: macroPropertyFilter(for: value)
            )

        case (_, .tuple?):
            dumpChildren(
                of: mirror,
                prefix: "(",
                suffix: ")",
                shouldSort: false,
                map: { child, _ in
                    if child.label?.first == "." {
                        child.label = nil
                    }
                }
            )

        default:
            out.write("\(value)")
        }

        target.write((name.map { "\($0)\(nameSuffix) " } ?? "").appending(out).indenting(by: indent))
    }

    customDumpHelp(
        value,
        to: &target,
        name: name,
        nameSuffix: nameSuffix,
        indent: indent,
        isRoot: isRoot,
        maxDepth: maxDepth
    )
    return value
}

private func _customDump(
    _ value: Any,
    name: String?,
    nameSuffix: String = ":",
    indent: Int,
    isRoot: Bool,
    maxDepth: Int,
    tracker: inout ObjectTracker
) -> String {
    var out = ""
    var t = tracker
    defer { tracker = t }
    _customDump(
        value,
        to: &out,
        name: name,
        nameSuffix: nameSuffix,
        indent: indent,
        isRoot: isRoot,
        maxDepth: maxDepth,
        tracker: &t
    )
    return out
}

extension Mirror {
    var isSingleValueContainer: Bool {
        switch self.displayStyle {
        case .collection?, .dictionary?, .set?:
            return false
        default:
            guard
                self.children.count == 1,
                let child = self.children.first
            else { return false }
            return Mirror(reflecting: child.value).children.isEmpty
        }
    }
}

private func macroPropertyFilter(for value: Any) -> (Mirror.Child) -> Bool {
    { $0.label.map { !$0.hasPrefix("_$") } ?? true }
}

extension String {
    func indenting(by count: Int) -> String {
        self.indenting(with: String(repeating: " ", count: count))
    }

    func indenting(with prefix: String) -> String {
        guard !prefix.isEmpty else {
            return self
        }
        return "\(prefix)\(self.replacingOccurrences(of: "\n", with: "\n\(prefix)"))"
    }

    func hashCount(isMultiline: Bool) -> Int {
        let (quote, offset) = isMultiline ? ("\"\"\"", 2) : ("\"", 0)
        var substring = self[...]
        var hashCount = 0
        let pattern = "(\(quote)[#]*)"
        while let range = substring.range(of: pattern, options: .regularExpression) {
            let count = substring.distance(from: range.lowerBound, to: range.upperBound) - offset
            hashCount = max(count, hashCount)
            substring = substring[range.upperBound...]
        }
        return hashCount
    }
}

internal enum Box<T> { }

// MARK: - Equatable

internal protocol AnyEquatable {
    static func isEqual(_ lhs: Any, _ rhs: Any) -> Bool
}

extension Box: AnyEquatable where T: Equatable {
    static func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        lhs as? T == rhs as? T
    }
}

private func isMirrorEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    func open<LHS>(_: LHS.Type) -> Bool? {
        (Box<LHS>.self as? AnyEquatable.Type)?.isEqual(lhs, rhs)
    }

    if let isEqual = _openExistential(type(of: lhs), do: open) {
        return isEqual
    }

    let lhsMirror = Mirror(reflecting: lhs)
    let rhsMirror = Mirror(reflecting: rhs)
    guard
        lhsMirror.subjectType == rhsMirror.subjectType,
        lhsMirror.children.count == rhsMirror.children.count
    else {
        return false
    }
    guard !lhsMirror.children.isEmpty, !rhsMirror.children.isEmpty else {
        return String(describing: lhs) == String(describing: rhs)
    }
    for (lhsChild, rhsChild) in zip(lhsMirror.children, rhsMirror.children) {
        guard
            lhsChild.label == rhsChild.label,
            isMirrorEqual(lhsChild.value, rhsChild.value)
        else {
            return false
        }
    }
    return true
}

internal protocol _UnorderedCollection {}
extension Dictionary: _UnorderedCollection {}
extension NSDictionary: _UnorderedCollection {}
extension NSSet: _UnorderedCollection {}
extension Set: _UnorderedCollection {}

public struct FileHandlerOutputStream: TextOutputStream {
    private let handle: FileHandle
    let encoding: String.Encoding

    public init(_ handle: FileHandle, encoding: String.Encoding = .utf8) {
        self.handle = handle
        self.encoding = encoding
    }

    public mutating func write(_ string: String) {
        if let data = string.data(using: encoding) {
            handle.seekToEndOfFile()
            handle.write(data)
        }
    }
}

// swiftlint:enable function_default_parameter_at_end

#endif
