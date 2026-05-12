/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A quantile sketch for computing approximate percentiles of a distribution
/// using logarithmic index mapping and bounded memory.
///
/// Ported from the Go reference:
/// https://github.com/DataDog/sketches-go/blob/master/ddsketch/ddsketch.go
///
/// This implementation is intentionally self-contained (no SDK dependencies)
/// so it can be extracted to a standalone repository.
///
/// Usage for client-side stats:
/// ```
/// var sketch = DDSketch.makeForStats()
/// sketch.add(durationInNanoseconds)
/// let protoBytes = sketch.toProtoBytes()
/// ```
internal struct DDSketch {
    let mapping: LogarithmicMapping
    private(set) var positiveStore: CollapsingLowestDenseStore
    private(set) var negativeStore: CollapsingLowestDenseStore
    private(set) var zeroCount: Double = 0

    private(set) var count: Double = 0
    private(set) var sum: Double = 0
    private(set) var min: Double = .infinity
    private(set) var max: Double = -.infinity

    /// Creates a DDSketch with the given relative accuracy and maximum bin count.
    ///
    /// - Parameters:
    ///   - relativeAccuracy: Controls bin width. 0.01 gives 1% relative accuracy.
    ///   - maxNumBins: Maximum number of bins per store. Excess bins are collapsed.
    init(relativeAccuracy: Double, maxNumBins: Int) {
        self.mapping = LogarithmicMapping(relativeAccuracy: relativeAccuracy)
        self.positiveStore = CollapsingLowestDenseStore(maxNumBins: maxNumBins)
        self.negativeStore = CollapsingLowestDenseStore(maxNumBins: maxNumBins)
    }

    /// Creates a DDSketch configured for client-side stats: 1% relative accuracy, 2048 max bins.
    static func makeForStats() -> DDSketch {
        return DDSketch(relativeAccuracy: 0.01, maxNumBins: 2_048)
    }

    /// Records a value into the sketch.
    ///
    /// - Parameter value: The value to record. For client-side stats, this is the span duration in nanoseconds.
    ///   NaN and infinite values are silently ignored.
    mutating func add(_ value: Double) {
        if value.isNaN || value.isInfinite {
            return
        }

        if value > mapping.minIndexableValue {
            if value > mapping.maxIndexableValue {
                return
            }
            let index = mapping.index(for: value)
            positiveStore.add(index: index, count: 1.0)
        } else if value < -mapping.minIndexableValue {
            if value < -mapping.maxIndexableValue {
                return
            }
            let index = mapping.index(for: -value)
            negativeStore.add(index: index, count: 1.0)
        } else {
            zeroCount += 1
        }

        count += 1
        sum += value
        if value < min { min = value }
        if value > max { max = value }
    }

    /// Returns whether the sketch has no recorded values.
    var isEmpty: Bool { count == 0 }

    /// Serializes the sketch to protobuf bytes matching the `DDSketch` message
    /// in `ddsketch.proto`.
    ///
    /// Wire layout:
    /// ```
    /// DDSketch {
    ///   1: IndexMapping { gamma, indexOffset, interpolation=NONE }
    ///   2: Store positiveValues { contiguousBinCounts, contiguousBinIndexOffset }
    ///   3: Store negativeValues { contiguousBinCounts, contiguousBinIndexOffset }
    ///   4: double zeroCount
    /// }
    /// ```
    func toProtoBytes() -> Data {
        var encoder = ProtoEncoder()

        let mappingBytes = encodeMappingProto()
        encoder.encodeNestedMessage(fieldNumber: 1, payload: mappingBytes)

        let posBytes = encodeStoreProto(positiveStore)
        encoder.encodeNestedMessage(fieldNumber: 2, payload: posBytes)

        let negBytes = encodeStoreProto(negativeStore)
        encoder.encodeNestedMessage(fieldNumber: 3, payload: negBytes)

        encoder.encodeDoubleField(fieldNumber: 4, value: zeroCount)

        return encoder.data
    }

    // MARK: - Protobuf Helpers

    private func encodeMappingProto() -> Data {
        var enc = ProtoEncoder()
        enc.encodeDoubleField(fieldNumber: 1, value: mapping.gamma)
        enc.encodeDoubleField(fieldNumber: 2, value: mapping.indexOffset)
        // interpolation = NONE (0) is proto3 default, omitted
        return enc.data
    }

    private func encodeStoreProto(_ store: CollapsingLowestDenseStore) -> Data {
        let (counts, indexOffset) = store.contiguousBins()
        if counts.isEmpty {
            return Data()
        }
        var enc = ProtoEncoder()
        enc.encodePackedDoubles(fieldNumber: 2, values: counts)
        enc.encodeSInt32Field(fieldNumber: 3, value: indexOffset)
        return enc.data
    }
}
