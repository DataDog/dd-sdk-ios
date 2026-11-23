/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftProtobuf

// Decodes the same bytes with SwiftProtobuf and with the hand-written decoder of DatadogFlags,
// compares every field, then compares decoding speed.

// MARK: - Helpers

func decodeBoth(_ data: Data) -> (PBConfig?, UFCFlagsConfiguration?) {
    (try? PBConfig(serializedBytes: data), try? UFCFlagsConfiguration(serializedData: data))
}

func compareDecoders(_ data: Data, _ label: String) -> Bool {
    let (g, h) = decodeBoth(data)
    guard let g, let h else {
        print("FAIL \(label): SwiftProtobuf=\(g != nil ? "ok" : "error") hand-written=\(h != nil ? "ok" : "error")")
        return false
    }
    var comparator = Comparator()
    comparator.config(g, h)
    if comparator.mismatches.isEmpty { return true }
    print("FAIL \(label): \(comparator.mismatches.count) mismatches, first: \(comparator.mismatches.prefix(3))")
    return false
}

func varint(_ value: UInt64) -> [UInt8] {
    var value = value
    var bytes: [UInt8] = []
    while value >= 0x80 { bytes.append(UInt8(value & 0x7F) | 0x80); value >>= 7 }
    bytes.append(UInt8(value))
    return bytes
}

func tag(_ number: UInt64, _ wireType: UInt64) -> [UInt8] { varint(number << 3 | wireType) }

func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

var sink = 0

func bench(_ label: String, _ data: Data, iterations: Int) {
    var protobufTimes: [Double] = []
    var handTimes: [Double] = []
    for round in 0..<(iterations + 10) {
        let t0 = now()
        let g = try! PBConfig(serializedBytes: data)
        let t1 = now()
        let h = try! UFCFlagsConfiguration(serializedData: data)
        let t2 = now()
        sink &+= g.flags.count &+ h.flags.count
        if round >= 10 {
            protobufTimes.append(Double(t1 - t0) / 1_000_000)
            handTimes.append(Double(t2 - t1) / 1_000_000)
        }
    }
    let p = median(protobufTimes), h = median(handTimes)
    print(String(format: "%@ (%d bytes): SwiftProtobuf %.3f ms, hand-written %.3f ms (%.2fx)", label, data.count, p, h, p / h))
}

// MARK: - Correctness

var failures = 0

let browserFixture = Data(base64Encoded: "CgQIABAAEgRwcm9kGm0KCXRlc3QtZmxhZxJgCAAQBBoECAAoASIsCgphbGxvY2F0aW9uEAAaDBIKCgRzYWx0EAEYZCIMCgQIABBkEAAYByABKAEiJgoIZmFsbGJhY2saDBIKCgRzYWx0EAEYZCIMCgQIABBkEAAYByACIgYSBAoCCAMiAgoAKgJvbioDb2ZmKgJVUyoHY291bnRyeTIEXlVTJDoJCgExCgEyCgEzSgYqBAgAEAJQAA==")!
if !compareDecoders(browserFixture, "browser fixture") { failures += 1 }

for seed in UInt64(1)...30 {
    let data = try! makeConfiguration(flags: 40, seed: seed).serializedBytes() as Data
    if !compareDecoders(data, "synthetic seed \(seed)") { failures += 1 }
}
let large = try! makeConfiguration(flags: 1_000, seed: 42).serializedBytes() as Data
if !compareDecoders(large, "synthetic 1,000 flags") { failures += 1 }

// Unknown fields of every wire type, at the top level, must be skipped by both decoders.
var withUnknown = [UInt8](browserFixture)
withUnknown += tag(1000, 0) + varint(123_456)
withUnknown += tag(1001, 1) + [UInt8](repeating: 7, count: 8)
withUnknown += tag(1002, 2) + varint(3) + [1, 2, 3]
withUnknown += tag(1003, 5) + [UInt8](repeating: 9, count: 4)
if !compareDecoders(Data(withUnknown), "unknown fields") { failures += 1 }

// Repeated uint32 in the unpacked encoding (SwiftProtobuf writes the packed one).
let operands = tag(1, 0) + varint(3) + tag(1, 0) + varint(5) + tag(1, 2) + varint(2) + varint(7) + varint(9)
let condition = tag(1, 2) + varint(UInt64(operands.count)) + operands
let unpacked = tag(9, 2) + varint(UInt64(condition.count)) + condition
if !compareDecoders(Data(unpacked), "unpacked repeated uint32") { failures += 1 }

// Invalid data must fail in both decoders.
let invalidCases: [(String, [UInt8])] = [
    ("truncated length", [0x0A, 0x05, 0x01]),
    ("truncated varint", [0x08, 0xFF]),
    ("11-byte varint", [0x08] + [UInt8](repeating: 0xFF, count: 10) + [0x01]),
    ("10-byte varint over 64 bits (both decoders accept and truncate)", [0x08] + [UInt8](repeating: 0xFF, count: 9) + [0x02]),
    ("field number 0", [0x00, 0x01]),
    ("group wire type", [0x0B]),
    ("invalid UTF-8 string", tag(2, 2) + varint(2) + [0xC3, 0x28]),
]
for (label, bytes) in invalidCases {
    let (g, h) = decodeBoth(Data(bytes))
    let result = "SwiftProtobuf=\(g == nil ? "error" : "ok") hand-written=\(h == nil ? "error" : "ok")"
    if (g == nil) != (h == nil) { failures += 1; print("FAIL invalid \(label): \(result)") } else { print("ok   invalid \(label): \(result)") }
}

// Random byte corruption: both decoders must agree on success or failure, and on the result.
var rng = SplitMix64(state: 7)
var agreeError = 0, agreeOK = 0, disagree = 0
let corpus = try! makeConfiguration(flags: 20, seed: 99).serializedBytes() as Data
for _ in 0..<5_000 {
    var bytes = [UInt8](corpus)
    var edits: [String] = []
    for _ in 0..<rng.int(1...3) {
        let position = rng.int(0...(bytes.count - 1))
        let value = UInt8(truncatingIfNeeded: rng.next())
        let context = bytes[max(0, position - 6)..<min(bytes.count, position + 7)].map { String(format: "%02x", $0) }.joined(separator: " ")
        edits.append("byte \(position): \(String(format: "%02x", bytes[position])) -> \(String(format: "%02x", value)) in [\(context)]")
        bytes[position] = value
    }
    if rng.int(0...4) == 0 { let n = rng.int(1...10); bytes.removeLast(n); edits.append("removed last \(n)") }
    let data = Data(bytes)
    let (g, h) = decodeBoth(data)
    switch (g, h) {
    case (nil, nil): agreeError += 1
    case let (g?, h?):
        var comparator = Comparator()
        comparator.config(g, h)
        if comparator.mismatches.isEmpty { agreeOK += 1 } else { disagree += 1 }
    default:
        disagree += 1
        if disagree <= 3 {
            var hError = "ok"
            do { _ = try UFCFlagsConfiguration(serializedData: data) } catch { hError = "\(error)" }
            var pError = "ok"
            do { _ = try PBConfig(serializedBytes: data) } catch { pError = "\(error)" }
            print("     corruption disagreement: SwiftProtobuf=\(pError) hand-written=\(hError); edits: \(edits)")
        }
    }
}
print("corruption fuzz: \(agreeOK) both ok and equal, \(agreeError) both error, \(disagree) disagree")
print(failures == 0 ? "CORRECTNESS: all checks pass" : "CORRECTNESS: \(failures) failures")
if failures > 0 {
    exit(1)
}

// MARK: - Speed

let medium = try! makeConfiguration(flags: 100, seed: 5).serializedBytes() as Data
bench("browser fixture, 1 flag", browserFixture, iterations: 20_000)
bench("synthetic, 100 flags", medium, iterations: 2_000)
bench("synthetic, 1,000 flags", large, iterations: 300)
print("sink \(sink)")
