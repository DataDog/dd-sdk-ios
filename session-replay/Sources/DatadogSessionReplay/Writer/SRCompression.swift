/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import _DatadogSessionReplay_Private

internal struct SRCompression {
    /// Compresses the data into ZLIB Compressed Data Format as described in IETF RFC 1950.
    ///
    /// To meet `dogweb` expectation for Session Replay, it uses compression level `6` and `Z_SYNC_FLUSH`
    /// + `Z_FINISH` flags for flushing compressed data to the output. This allows the receiver (SR player) to
    /// concatenate succeeding chunks of compressed data and perform inflate only once instead of decompressing
    /// each chunk individually.
    static func compress(data: Data) throws -> Data {
        return try __dd_srprivate_ZlibCompression.compress(data, level: 6)
    }
}
