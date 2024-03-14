/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Default max data length in TLV block for batch file (safety check) - 10 MB
internal let MAX_DATA_LENGTH: UInt64 = 10.MB.asUInt64()

/// TLV block type used in batch files.
internal enum BatchBlockType: UInt16, TLVBlockType {
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
