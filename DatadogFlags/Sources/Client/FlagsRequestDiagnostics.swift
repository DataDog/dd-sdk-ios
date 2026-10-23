/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Ephemeral identity and sequence owned by one repository, never used for evaluation or persistence.
internal final class FlagsRequestDiagnostics {
    enum Trigger: String {
        case initialization
        case contextChange = "context_change"
    }

    private let lock = NSLock()
    private let instanceID: String
    private var sequence: Int64 = 0

    init(now: Date = Date()) {
        instanceID = UUIDv7Generator.generate(now: now).uuidString.lowercased()
    }

    /// UUIDv7 polyfill for supported Foundation versions without a UUIDv7 factory.
    enum UUIDv7Generator {
        static func generate(now: Date) -> UUID {
            // RFC 9562: 48-bit Unix milliseconds, version 7, RFC variant, and 74 random bits.
            let milliseconds = now.timeIntervalSince1970 * 1_000
            let timestamp = UInt64(milliseconds.isFinite ? min(max(0, milliseconds), 281_474_976_710_655) : 0)
            var bytes = UUID().uuid
            withUnsafeMutableBytes(of: &bytes) { buffer in
                for index in 0..<6 {
                    buffer[index] = UInt8(truncatingIfNeeded: timestamp >> ((5 - index) * 8))
                }
                buffer[6] = (buffer[6] & 0x0f) | 0x70
                buffer[8] = (buffer[8] & 0x3f) | 0x80
            }
            return UUID(uuid: bytes)
        }
    }

    func accept() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        // The first accepted context initialises this repository; subsequent calls change context.
        let trigger: Trigger = sequence == 0 ? .initialization : .contextChange
        sequence = min(sequence + 1, 9_007_199_254_740_991)
        let envelope: [String: AnyValue] = [
            "sdk": .dictionary(["instance_id": .string(instanceID)]),
            "fetch": .dictionary([
                "sequence": .double(Double(sequence)),
                "trigger": .string(trigger.rawValue)
            ])
        ]
        guard let data = try? JSONEncoder().encode(envelope), data.count <= 4_096 else {
            return nil
        }
        return data
    }
}
