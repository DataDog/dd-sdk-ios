/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A contiguous array of bin counts that collapses the lowest bins when the
/// number of bins exceeds `maxNumBins`.
///
/// Ported from the Go reference:
/// https://github.com/DataDog/sketches-go/blob/master/ddsketch/store/collapsing_lowest_dense_store.go
///
/// Collapsing the lowest bins trades accuracy on the lowest quantiles for bounded
/// memory usage. This is the correct trade-off for latency distributions where
/// higher percentiles (p50, p90, p99) matter more than p1.
///
/// ### Storage model
///
/// Bin indices can be any signed integer (positive or negative), but the backing
/// array `bins` is a flat `[Double]` indexed from `0`. The mapping between a logical
/// bin index `i` and its position in `bins` is:
///
///     bins[i - offset]
///
/// `offset` is the logical index of `bins[0]`. `minIndex` and `maxIndex` track the
/// range of logical indices that currently hold non-zero counts. The store may
/// reserve more array slots than this range (e.g. after collapsing).
///
/// ### Collapsing
///
/// When inserting a new index would require more than `maxNumBins` bins to span
/// `[minIndex, maxIndex]`, the store collapses the lowest bins: the new logical
/// range becomes `[newMax - maxNumBins + 1, newMax]`, and all counts below that
/// new minimum are folded into the lowest surviving bin. Once collapsed,
/// `isCollapsed` stays `true` for the lifetime of the store.
internal struct CollapsingLowestDenseStore {
    /// Flat array of bin counts. `bins[i - offset]` holds the count for logical bin `i`.
    /// May contain trailing zeros beyond `maxIndex` due to capacity reservation.
    private(set) var bins: [Double]

    /// Sum of all bin counts. Updated incrementally by `add`.
    private(set) var count: Double = 0

    /// Lowest logical bin index currently in use. Undefined when the store is empty.
    private(set) var minIndex: Int = 0

    /// Highest logical bin index currently in use. Undefined when the store is empty.
    private(set) var maxIndex: Int = 0

    /// Logical index corresponding to `bins[0]`. Adjusted when the range shifts.
    private(set) var offset: Int = 0

    /// `true` once the store has collapsed at least once. Drives the fast path in `add`
    /// for values below `minIndex`.
    private(set) var isCollapsed: Bool = false

    /// Maximum number of bins the store will allocate before collapsing.
    let maxNumBins: Int

    /// `true` until the first non-zero `add(index:count:)` call.
    private var isEmpty: Bool = true

    init(maxNumBins: Int) {
        precondition(maxNumBins > 0, "maxNumBins must be positive")
        self.maxNumBins = maxNumBins
        self.bins = []
    }

    /// Adds `count` to the bin at the given logical `index`, extending or collapsing
    /// the backing array as needed.
    ///
    /// - If `index` falls inside `[minIndex, maxIndex]`, the count is added in place.
    /// - If `index` is below `minIndex` and the store is already collapsed, the count
    ///   is folded into the lowest surviving bin.
    /// - Otherwise, the range is extended and may trigger a collapse if it would
    ///   exceed `maxNumBins`.
    ///
    /// Passing `count == 0` is a no-op.
    mutating func add(index: Int, count: Double) {
        if count == 0 {
            return
        }

        if isEmpty {
            setupFirstValue(index: index)
        }

        if index < minIndex {
            if isCollapsed {
                bins[minIndex - offset] += count
                self.count += count
                return
            }
            extendRange(newMin: index, newMax: maxIndex)
            if isCollapsed {
                bins[minIndex - offset] += count
                self.count += count
                return
            }
        } else if index > maxIndex {
            extendRange(newMin: minIndex, newMax: index)
        }

        bins[index - offset] += count
        self.count += count
    }

    /// Returns the contiguous bin data for protobuf serialization.
    /// The `indexOffset` is the logical index of the first bin in the returned slice.
    /// The slice borrows from `bins` directly to avoid copying.
    func contiguousBins() -> (counts: ArraySlice<Double>, indexOffset: Int32) {
        if isEmpty {
            return ([], 0)
        }

        let startArrayIndex = bins.startIndex.advanced(by: minIndex - offset)
        let endArrayIndex = bins.startIndex.advanced(by: maxIndex - offset)
        return (bins[startArrayIndex...endArrayIndex], Int32(minIndex))
    }

    // MARK: - Private

    /// Initialises the store on its first `add` call: a single bin centred on `index`
    /// with `offset == index` so the new value sits at `bins[0]`.
    private mutating func setupFirstValue(index: Int) {
        isEmpty = false
        minIndex = index
        maxIndex = index
        offset = index
        bins = [0]
    }

    /// Extends `[minIndex, maxIndex]` to cover `[newMin, newMax]`, allocating more
    /// capacity if needed. If the resulting range would exceed `maxNumBins`,
    /// delegates to `collapse` instead.
    private mutating func extendRange(newMin: Int, newMax: Int) {
        let requiredBins = newMax - newMin + 1

        if requiredBins > maxNumBins {
            collapse(newMin: newMin, newMax: newMax)
            return
        }

        if newMax > maxIndex {
            let neededCapacity = newMax - offset + 1
            if neededCapacity > bins.count {
                bins.append(contentsOf: [Double](repeating: 0, count: neededCapacity - bins.count))
            }
            maxIndex = newMax
        }

        if newMin < minIndex {
            let shift = offset - newMin
            if shift > 0 {
                let newBins = [Double](repeating: 0, count: shift) + bins
                bins = newBins
                offset = newMin
            }
            minIndex = newMin
        }
    }

    /// Rebuilds the bins array to cover exactly `[adjustedMin, newMax]` within
    /// `maxNumBins`. Values below `adjustedMin` are folded into the lowest surviving
    /// bin.
    ///
    /// The new array is assembled as four concatenated slices:
    /// `[leading zeros] + [fold] + [preserved] + [trailing zeros]`,
    /// each of which may be empty depending on whether this is a downward
    /// (`adjustedMin <= minIndex`) or upward (`adjustedMin > minIndex`) collapse.
    private mutating func collapse(newMin: Int, newMax: Int) {
        let adjustedMin = newMax - maxNumBins + 1

        if bins.isEmpty || adjustedMin >= maxIndex {
            bins = [Double](repeating: 0, count: maxNumBins)
            bins[0] = count
            offset = adjustedMin
            minIndex = adjustedMin
            maxIndex = newMax
            isCollapsed = true
            return
        }

        let leadingZeros: [Double]
        let fold: [Double]
        let preservedStartIdx: Int

        if adjustedMin > minIndex {
            // Upward collapse: sum bins in `[minIndex, adjustedMin]` into a single
            // bin at the new floor.
            let foldStart = bins.startIndex.advanced(by: minIndex - offset)
            let foldEnd = bins.startIndex.advanced(by: adjustedMin - offset)
            let foldedCount = bins[foldStart...foldEnd].reduce(0, +)
            leadingZeros = []
            fold = [foldedCount]
            preservedStartIdx = adjustedMin + 1
        } else {
            // Downward collapse (or no shift): pad zeros on the left, then copy
            // the preserved range verbatim.
            leadingZeros = [Double](repeating: 0, count: minIndex - adjustedMin)
            fold = []
            preservedStartIdx = minIndex
        }

        let preserved: [Double]
        if preservedStartIdx <= maxIndex {
            let srcStart = bins.startIndex.advanced(by: preservedStartIdx - offset)
            let srcEnd = bins.startIndex.advanced(by: maxIndex - offset)
            preserved = Array(bins[srcStart...srcEnd])
        } else {
            preserved = []
        }

        let trailingZeros = [Double](
            repeating: 0,
            count: maxNumBins - leadingZeros.count - fold.count - preserved.count
        )
        bins = leadingZeros + fold + preserved + trailingZeros

        offset = adjustedMin
        minIndex = adjustedMin
        maxIndex = newMax
        isCollapsed = true
    }
}
