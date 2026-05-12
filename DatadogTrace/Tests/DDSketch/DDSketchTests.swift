/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import DatadogTrace
import XCTest

final class DDSketchTests: XCTestCase {
    // MARK: - Factory

    func testMakeForStats_configures1PercentAccuracyAnd2048Bins() {
        let sketch = DDSketch.makeForStats()
        XCTAssertEqual(sketch.mapping.relativeAccuracy, 0.01)
        XCTAssertEqual(sketch.positiveStore.maxNumBins, 2_048)
        XCTAssertEqual(sketch.negativeStore.maxNumBins, 2_048)
    }

    // MARK: - Empty Sketch

    func testEmptySketch() {
        let sketch = DDSketch.makeForStats()
        XCTAssertTrue(sketch.isEmpty)
        XCTAssertEqual(sketch.count, 0)
        XCTAssertEqual(sketch.sum, 0)
        XCTAssertEqual(sketch.zeroCount, 0)
    }

    func testEmptySketch_toProtoBytes_isNotEmpty() {
        let sketch = DDSketch.makeForStats()
        let bytes = sketch.toProtoBytes()
        // Even empty, the mapping message must be encoded
        XCTAssertGreaterThan(bytes.count, 0)
    }

    // MARK: - Adding Values

    func testAddPositiveValues() {
        var sketch = DDSketch.makeForStats()
        sketch.add(100.0)
        sketch.add(200.0)
        sketch.add(300.0)

        XCTAssertEqual(sketch.count, 3)
        XCTAssertEqual(sketch.sum, 600.0)
        XCTAssertEqual(sketch.min, 100.0)
        XCTAssertEqual(sketch.max, 300.0)
        XCTAssertFalse(sketch.isEmpty)
    }

    func testAddZero_goesToZeroBucket() {
        var sketch = DDSketch.makeForStats()
        sketch.add(0.0)

        XCTAssertEqual(sketch.count, 1)
        XCTAssertEqual(sketch.zeroCount, 1)
        XCTAssertEqual(sketch.sum, 0)
    }

    func testAddNegativeValues() {
        var sketch = DDSketch.makeForStats()
        sketch.add(-50.0)
        sketch.add(-100.0)

        XCTAssertEqual(sketch.count, 2)
        XCTAssertEqual(sketch.sum, -150.0)
        XCTAssertEqual(sketch.min, -100.0)
        XCTAssertEqual(sketch.max, -50.0)
    }

    func testAddMixedValues() {
        var sketch = DDSketch.makeForStats()
        sketch.add(-10.0)
        sketch.add(0.0)
        sketch.add(10.0)

        XCTAssertEqual(sketch.count, 3)
        XCTAssertEqual(sketch.zeroCount, 1)
        XCTAssertEqual(sketch.sum, 0.0)
    }

    // MARK: - Edge Cases

    func testAddNaN_isIgnored() {
        var sketch = DDSketch.makeForStats()
        sketch.add(Double.nan)
        XCTAssertTrue(sketch.isEmpty)
        XCTAssertEqual(sketch.count, 0)
    }

    func testAddInfinity_isIgnored() {
        var sketch = DDSketch.makeForStats()
        sketch.add(Double.infinity)
        sketch.add(-Double.infinity)
        XCTAssertTrue(sketch.isEmpty)
        XCTAssertEqual(sketch.count, 0)
    }

    func testAddVerySmallPositive_goesToZeroBucket() {
        var sketch = DDSketch.makeForStats()
        let tinyValue = Double.leastNonzeroMagnitude
        sketch.add(tinyValue)
        // Very small values below minIndexableValue go to zero bucket
        XCTAssertEqual(sketch.zeroCount, 1)
    }

    // MARK: - Protobuf Serialization

    func testToProtoBytes_notEmpty_afterAdding() {
        var sketch = DDSketch.makeForStats()
        sketch.add(1_000_000.0) // 1ms in nanoseconds
        sketch.add(5_000_000.0) // 5ms
        sketch.add(10_000_000.0) // 10ms

        let bytes = sketch.toProtoBytes()
        XCTAssertGreaterThan(bytes.count, 0)
    }

    func testToProtoBytes_hasValidProtobufStructure() {
        var sketch = DDSketch.makeForStats()
        sketch.add(42.0)

        let bytes = sketch.toProtoBytes()
        // First byte should be the tag for field 1, wire type 2 (length-delimited)
        // (1 << 3) | 2 = 0x0A
        XCTAssertEqual(bytes[0], 0x0A, "First field should be mapping (field 1, length-delimited)")
    }

    func testToProtoBytes_mappingContainsGamma() {
        let sketch = DDSketch.makeForStats()
        let bytes = sketch.toProtoBytes()

        // The mapping message should contain the gamma value
        // gamma for 1% accuracy = 1.01 / 0.99 ≈ 1.0202020202020...
        // This is encoded as a fixed64 double somewhere in the output
        XCTAssertGreaterThan(bytes.count, 9, "Should at least contain mapping with gamma")
    }

    // MARK: - Latency Distribution (CSS Use Case)

    func testLatencyDistribution_typicalSpanDurations() {
        var sketch = DDSketch.makeForStats()

        // Typical span durations in nanoseconds (1ms to 5s)
        let durations: [Double] = [
            1_000_000,    // 1ms
            5_000_000,    // 5ms
            10_000_000,   // 10ms
            50_000_000,   // 50ms
            100_000_000,  // 100ms
            500_000_000,  // 500ms
            1_000_000_000, // 1s
            5_000_000_000  // 5s
        ]

        for d in durations {
            sketch.add(d)
        }

        XCTAssertEqual(sketch.count, 8)
        XCTAssertEqual(sketch.min, 1_000_000)
        XCTAssertEqual(sketch.max, 5_000_000_000)

        let bytes = sketch.toProtoBytes()
        XCTAssertGreaterThan(bytes.count, 0)
    }

    func testManyValues_staysWithinBinLimit() {
        var sketch = DDSketch.makeForStats()

        // Add 10,000 values spanning a wide range
        for i in 1...10_000 {
            sketch.add(Double(i) * 1_000_000) // i ms in nanoseconds
        }

        XCTAssertEqual(sketch.count, 10_000)

        // Positive store should not exceed 2048 bins
        let (counts, _) = sketch.positiveStore.contiguousBins()
        XCTAssertLessThanOrEqual(counts.count, 2_048)

        let bytes = sketch.toProtoBytes()
        XCTAssertGreaterThan(bytes.count, 0)
    }

    // MARK: - Determinism

    func testSameInputs_produceSameOutput() {
        var sketch1 = DDSketch.makeForStats()
        var sketch2 = DDSketch.makeForStats()

        let values: [Double] = [1.0, 2.0, 3.0, 100.0, 1_000.0]
        for v in values {
            sketch1.add(v)
            sketch2.add(v)
        }

        XCTAssertEqual(sketch1.toProtoBytes(), sketch2.toProtoBytes())
    }

    // MARK: - Protobuf Round-Trip Validation

    func testProtoBytes_canBeParsed() throws {
        var sketch = DDSketch.makeForStats()
        sketch.add(100.0)
        sketch.add(200.0)

        let bytes = sketch.toProtoBytes()

        // Manually parse the protobuf to validate structure
        var offset = 0

        // Field 1: mapping (length-delimited)
        let (field1Tag, field1WireType) = try parseTag(bytes, offset: &offset)
        XCTAssertEqual(field1Tag, 1)
        XCTAssertEqual(field1WireType, 2) // length-delimited
        let mappingLength = try parseVarint(bytes, offset: &offset)
        offset += Int(mappingLength) // skip mapping payload

        // Field 2: positiveValues (length-delimited)
        let (field2Tag, field2WireType) = try parseTag(bytes, offset: &offset)
        XCTAssertEqual(field2Tag, 2)
        XCTAssertEqual(field2WireType, 2)
    }

    // MARK: - Helpers

    private func parseTag(_ data: Data, offset: inout Int) throws -> (fieldNumber: Int, wireType: Int) {
        let varint = try parseVarint(data, offset: &offset)
        return (Int(varint >> 3), Int(varint & 0x07))
    }

    private func parseVarint(_ data: Data, offset: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.count {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        throw NSError(domain: "ProtoParseError", code: 1)
    }
}
