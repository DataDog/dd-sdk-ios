/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Max data length in a TLV block for batch upload files - matches the server's 5 MB per-batch limit.
internal let maxTLVDataLength: TLVBlockSize = 5.MB.asUInt32()

/// Max data length in a TLV block for data-store files - separate from the batch upload limit.
internal let maxDataStoreTLVDataLength: TLVBlockSize = 10.MB.asUInt32()

/// TLV block type used in batch files.
internal enum BatchBlockType: UInt16 {
    /// Represents an event
    case event = 0x00
    /// Represents an event metadata associated with the previous event.
    /// This block is optional and may be omitted.
    case eventMetadata = 0x01
}

/// TLV data block stored in batch files.
internal typealias BatchDataBlock = TLVBlock<BatchBlockType>

/// TLV reader for batch files.
internal typealias BatchDataBlockReader = TLVBlockReader<BatchBlockType>
