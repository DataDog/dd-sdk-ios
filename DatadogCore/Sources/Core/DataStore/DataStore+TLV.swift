/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Represents the type of TLV block used in Data Store files.
internal enum DataStoreBlockType: UInt16, TLVBlockType {
    /// The version of data format in `data` block.
    case version = 0x00
    /// The actual data stored in the file.
    case data = 0x01
}

/// Represents a TLV data block stored in data store files.
internal typealias DataStoreBlock = TLVBlock<DataStoreBlockType>

/// Represents a TLV reader for data store files.
internal typealias DataStoreBlockReader = TLVBlockReader<DataStoreBlockType>
