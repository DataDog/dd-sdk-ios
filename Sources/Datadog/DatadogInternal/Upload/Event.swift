/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Struct representing a single event.
public struct Event: Equatable {
    /// Data representing the event.
    public let data: Data

    /// Metadata associated with the event.
    /// Metadata is optional and may be `nil` but of very small size.
    /// This allows us to skip resource intensive operations in case such
    /// as filtering of the events.
    public let metadata: Data?

    public init(data: Data, metadata: Data? = nil) {
        self.data = data
        self.metadata = metadata
    }
}

/// Event generator that generates events from the given data blocks.
internal struct EventGenerator: Sequence, IteratorProtocol {
    private let dataBlocks: [DataBlock]
    private var index: Int

    init(dataBlocks: [DataBlock], index: Int = 0) {
        self.dataBlocks = dataBlocks
        self.index = index
    }

    /// Returns the next event.
    /// - Returns: The next event or `nil` if there are no more events.
    /// - Note: a `DataBlock` with `.event` type marks the beginning of the event.
    ///         It is either followed by another `DataBlock` with `.event` type or
    ///         by a `DataBlock` with `.metadata` type.
    mutating func next() -> Event? {
        guard index < dataBlocks.count else {
            return nil
        }

        let event = dataBlocks[index]
        index += 1
        // if the first block is not event, then skip it
        guard event.type == .event else {
            return next()
        }

        // if the next block is also event, then there is no metadata
        guard index < dataBlocks.count, dataBlocks[index].type != .event else {
            return Event(data: event.data, metadata: nil)
        }

        // otherwise, the next block can be metadata
        let metadata = dataBlocks[index]
        guard metadata.type == .eventMetadata else {
            return Event(data: event.data, metadata: nil)
        }
        index += 1

        return Event(data: event.data, metadata: metadata.data)
    }
}
