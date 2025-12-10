/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

internal typealias DiffableID = Int64

/// A base interface of array elements compared in `computeDiff(oldArray:newArray:)`.
internal protocol Diffable {
    /// Unique identifier of elements in `oldArray` and `newArray`.
    ///
    /// It is used to determinen the type of mutation applied to the element:
    /// - "add" - if certain `id` exists in `newArray`, but not in `oldArray`,
    /// - "remove" - if certain `id` exists in `oldArray`, but not in `newArray`,
    /// - "update" - if certain `id` exists in both arrays and `isDifferent(than:)` returns `true`.
    var id: DiffableID { get }

    /// Determines if this element has any changes if compared to other element.
    /// It is used from `computeDiff(oldArray:newArray:)`. Both elements are guaranteed to have the same `id`.
    /// - Parameter otherElement: the element to compare against
    /// - Returns: `true` if data in both elements is different; `false` otherwise
    func isDifferent(than otherElement: Self) -> Bool
}

/// Describes differences between both arrays compared in `computeDiff(oldArray:newArray:)`. It lists minimal
/// set of changes that needs to be applied to `oldArray` to result with `newArray`.
///
/// Note:
/// - when reconstructing `newArray` from `oldArray` and `Diff` **removals must be applied before additions**;
/// - if certain element changes its position in `newArray`, `Diff` includes its **removal and addition** (on new position).
internal struct Diff<Element: Diffable> {
    /// Dictates that new element was added in `newArray`.
    struct Add {
        /// The `id` of preceding element in `newArray` or `nil` if new element should be inserted at index `0`.
        let previousID: DiffableID?
        /// The element to add.
        let new: Element
    }

    /// Dictates that given element exists in both arrays but its data was changed.
    struct Update {
        /// Previous version of element (it has the same `id` as `to`).
        let from: Element
        /// New version of element (it has the same `id` as `from`).
        let to: Element
    }

    /// Dictates that element was removed from `oldArray`.
    struct Remove {
        /// The `id` of element to remove.
        let id: DiffableID
    }

    /// Elements to add.
    let adds: [Add]
    /// Elements to update (change data).
    let updates: [Update]
    /// Elements to remove.
    let removes: [Remove]

    /// If diff has no changes.
    /// Empty diff indicates that arrays compared in `computeDiff(oldArray:newArray:)` are equal.
    var isEmpty: Bool {
        return adds.isEmpty && updates.isEmpty && removes.isEmpty
    }
}

/// Thrown if unexpected happened in implemented algorithm.
internal struct DiffError: Error {}

/// An item in symbols table (`[DiffableID: Symbol]`) in Heckel's algorithm.
///
/// Note: Unlike original algorithm, our implementation doesn't use `OC`, `NC` and `OLNO` counters. In our case, elements within each array are unique,
/// so instead of repetition counters, we define basic `inNew` flag and optional `indexInOld` to track occurrence of certain `id` in one or both files.
private struct Symbol {
    /// If element with certain `id` occurs in `newArray`.
    var inNew: Bool
    /// The index of element in `oldArray` (or `nil` if the element is not there).
    var indexInOld: Int?
}

/// An entry in `oa` (old array) and `na` (new array) arrays in Heckel's algorithm.
private enum Entry: Equatable {
    /// Reference to `Symbol` in `table: [DiffableID: Symbol]`.
    case reference(DiffableID)
    /// Index of element in other array (in `oldArray` for `na: [Entry]` and in `newArray` for `oa: [Entry]`).
    case index(Int)
}

/// Computes a diff between two arrays.
///
/// This implementation is based on Paul Heckel's algorithm for finding differences between files. It isolates differences in a way that corresponds
/// closely to our intuitive notion of difference (it finds the longest common subsequence). It is computationally efficient: `O(n)` in time and memory.
///
/// Unlike original Heckel's algorithm, our implementation assumes that elements are unique within each of two arrays. It means that all elements in
/// `oldArray` are guaranteed to have different `id` (same for `newArray`). Elements with the same `id` can appear in both arrays, which
/// indicates one of two things determined by `newElement.isDifferent(than: oldElement)`:
/// - either the element was not altered and can be skipped in diff,
/// - or the element was changed and it should be reflected in `Diff.Update`.
///
/// Like original algorithm, our implementation uses 6 passes over both arrays to determine diff
///
/// Ref.:
/// - _"A technique for isolating differences between files"_ Paul Heckel (1978) - https://dl.acm.org/citation.cfm?id=359467
///
/// - Parameters:
///   - oldArray: original array
///   - newArray: new array
/// - Returns: `Diff` describing changes from `oldArray` to `newArray`.
internal func computeDiff<E: Diffable>(oldArray: [E], newArray: [E]) throws -> Diff<E> {
    var table: [DiffableID: Symbol] = [:]
    var oa: [Entry] = [] // old array entries
    var na: [Entry] = [] // new array entries

    // 1st pass
    // Read `newArray` and store info on each element in symbols `table`:
    for element in newArray {
        table[element.id] = Symbol(inNew: true, indexInOld: nil)
        na.append(.reference(element.id))
    }

    // 2nd pass
    // Read `oldArray` and store info on each element in symbols `table`. If certain element already
    // exists, update its information (otherwise create new entry):
    for (index, element) in oldArray.enumerated() {
        if table[element.id] == nil {
            table[element.id] = Symbol(inNew: false, indexInOld: index)
        } else {
            table[element.id]?.indexInOld = index
        }
        oa.append(.reference(element.id))
    }

    // 3rd pass
    // Uses "Observation 1":
    // > If a line occurs only once in each file, then it must be the same line, although it may have been moved.
    // > We use this observation to locate unaltered lines that we subsequently exclude from further treatment.
    for (index, entry) in na.enumerated() {
        if case let .reference(id) = entry {
            guard let symbol = table[id] else {
                throw DiffError()
            }
            if symbol.inNew, let indexInOld = symbol.indexInOld {
                na[index] = .index(indexInOld)
                oa[indexInOld] = .index(index)
            }
        }
    }

    // 4th pass
    // > If a line has been found to be unaltered, and the lines immediately adjacent to it in both files are identical,
    // > then these lines must be the same line. This information can be used to find blocks of unchanged lines.
    if na.count > 1 {
        for i in (0..<(na.count - 1)) {
            if case let .index(j) = na[i], j + 1 < oa.count {
                if case let .reference(id1) = na[i + 1], case let .reference(id2) = oa[j + 1], id1 == id2 {
                    na[i + 1] = .index(j + 1)
                    oa[j + 1] = .index(i + 1)
                }
            }
        }
    }

    // 5th pass
    // Similar to 4th pass, except it processes entries in descending order.
    if na.count > 1 {
        for i in (1..<na.count).reversed() {
            if case let .index(j) = na[i], j - 1 >= 0 {
                if case let .reference(id1) = na[i - 1], case let .reference(id2) = oa[j - 1], id1 == id2 {
                    na[i - 1] = .index(j - 1)
                    oa[j - 1] = .index(i - 1)
                }
            }
        }
    }

    // Final pass
    // Constructing the actual diff from information stored in `oa` and `na`.
    var adds: [Diff<E>.Add] = []
    var updates: [Diff<E>.Update] = []
    var removes: [Diff<E>.Remove] = []

    var removalOffsets = Array(repeating: 0, count: oldArray.count)
    var runningOffset = 0

    for (i, entry) in oa.enumerated() {
        removalOffsets[i] = runningOffset
        if case .reference = entry {
            // Old element was removed:
            removes.append(.init(id: oldArray[i].id))
            runningOffset += 1
        }
    }

    runningOffset = 0

    for (i, entry) in na.enumerated() {
        switch entry {
        case let .index(indexInOld):
            let removalOffset = removalOffsets[indexInOld]
            let newElement = newArray[i]
            let oldElement = oldArray[indexInOld]

            if (indexInOld - removalOffset + runningOffset) != i {
                // Old element was moved to another position:
                let previousID: DiffableID? = i > 0 ? newArray[(i - 1)].id : nil
                removes.append(.init(id: newArray[i].id))
                adds.append(.init(previousID: previousID, new: newArray[i]))
            } else if newElement.isDifferent(than: oldElement) {
                // Existing element is on the right position, but its data is different
                updates.append(.init(from: oldElement, to: newElement))
            } // else - element was not moved and not changed, so: skip
        case .reference:
            // New element was added:
            let previousID: DiffableID? = i > 0 ? newArray[(i - 1)].id : nil
            adds.append(.init(previousID: previousID, new: newArray[i]))
            runningOffset += 1
        }
    }

    return Diff(adds: adds, updates: updates, removes: removes)
}
#endif
