/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// FNV-1a 64-bit hash utility.
///
/// Used to produce a stable hash of peer tag key-value pairs for stats aggregation.
/// The format matches the Go reference implementation: sorted `"key=value,"` pairs
/// fed byte-by-byte into FNV-1a.
internal enum FNV1aHash {
    private static let offsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let prime: UInt64 = 1_099_511_628_211

    /// Hashes the subset of `peerTags` whose keys appear in `keys`.
    ///
    /// - Returns: 0 when no matching peer tags are found.
    static func hash(peerTags tags: [String: String], keys: [String]) -> UInt64 {
        let pairs = keys
            .compactMap { key -> (String, String)? in
                guard let value = tags[key], !value.isEmpty else {
                    return nil
                }
                return (key, value)
            }
        let relevant = pairs
            .sorted { $0.0 < $1.0 }

        guard !relevant.isEmpty else {
            return 0
        }

        var hash = offsetBasis
        for (key, value) in relevant {
            for byte in "\(key)=\(value),".utf8 {
                hash ^= UInt64(byte)
                hash &*= prime
            }
        }
        return hash
    }
}
