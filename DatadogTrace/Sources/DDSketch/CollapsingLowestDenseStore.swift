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
internal struct CollapsingLowestDenseStore {
    private(set) var bins: [Double]
    private(set) var count: Double = 0
    private(set) var minIndex: Int = 0
    private(set) var maxIndex: Int = 0
    private(set) var offset: Int = 0
    private(set) var isCollapsed: Bool = false
    let maxNumBins: Int
    private var isEmpty: Bool = true

    init(maxNumBins: Int) {
        precondition(maxNumBins > 0, "maxNumBins must be positive")
        self.maxNumBins = maxNumBins
        self.bins = []
    }

    /// Adds `count` to the bin at the given index, extending or collapsing as needed.
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

        let arrayIndex = index - offset
        bins[arrayIndex] += count
        self.count += count
    }

    /// Returns the contiguous bin data for protobuf serialization.
    /// The `offset` is the index of the first bin in the contiguous array.
    func contiguousBins() -> (counts: [Double], indexOffset: Int32) {
        if isEmpty {
            return ([], 0)
        }

        let startArrayIndex = minIndex - offset
        let endArrayIndex = maxIndex - offset
        let slice = Array(bins[startArrayIndex...endArrayIndex])
        return (slice, Int32(minIndex))
    }

    // MARK: - Private

    private mutating func setupFirstValue(index: Int) {
        isEmpty = false
        minIndex = index
        maxIndex = index
        offset = index
        bins = [0]
    }

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

    /// Rebuilds the bins array to cover exactly `adjustedMin...newMax` within `maxNumBins`.
    /// Values below `adjustedMin` are folded into the lowest surviving bin.
    private mutating func collapse(newMin: Int, newMax: Int) {
        let adjustedMin = newMax - maxNumBins + 1

        if bins.isEmpty || adjustedMin >= maxIndex {
            let totalCount = count
            bins = [Double](repeating: 0, count: maxNumBins)
            bins[0] = totalCount
            offset = adjustedMin
            minIndex = adjustedMin
            maxIndex = newMax
            isCollapsed = true
            return
        }

        var newBins = [Double](repeating: 0, count: maxNumBins)
        for oldIdx in minIndex...maxIndex {
            let srcArrayIdx = oldIdx - offset
            if srcArrayIdx < 0 || srcArrayIdx >= bins.count {
                continue
            }
            let dstIdx = max(oldIdx, adjustedMin)
            let dstArrayIdx = dstIdx - adjustedMin
            if dstArrayIdx >= 0 && dstArrayIdx < newBins.count {
                newBins[dstArrayIdx] += bins[srcArrayIdx]
            }
        }

        bins = newBins
        offset = adjustedMin
        minIndex = adjustedMin
        maxIndex = newMax
        isCollapsed = true
    }
}
