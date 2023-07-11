/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Event generator that generates events from the given data blocks.
internal struct EventGenerator: Sequence, IteratorProtocol {
    private let dataBlocks: [DataBlock]
    private var index: Int

    init(dataBlocks: [DataBlock], index: Int = 0) {
        self.dataBlocks = dataBlocks
        self.index = index
    }

    /// Returns the next event.
    ///
    /// Data format
    /// ```
    /// [EVENT 1 METADATA] [EVENT 1] [EVENT 2 METADATA] [EVENT 2] [EVENT 3]
    /// ```
    ///
    /// - Returns: The next event or `nil` if there are no more events.
    /// - Note: a `DataBlock` with `.event` type marks the beginning of the event.
    ///         It is either followed by another `DataBlock` with `.event` type or
    ///         by a `DataBlock` with `.metadata` type.
    mutating func next() -> Event? {
        guard index < dataBlocks.count else {
            return nil
        }

        var metadata: DataBlock? = nil
        // If the next block is an event metadata, read it.
        if dataBlocks[index].type == .eventMetadata {
            metadata = dataBlocks[index]
            index += 1
        }

        // If this is the last block, return nil.
        // there cannot be a metadata block without an event block.
        guard index < dataBlocks.count else {
            return nil
        }

        // If the next block is an event, read it.
        guard dataBlocks[index].type == .event else {
            // this is safeguard against corrupted data.
            // if there was a metadata block, it will be skipped.
            return next()
        }
        let event = dataBlocks[index]
        index += 1

        return Event(data: event.data, metadata: metadata?.data)
    }
}
