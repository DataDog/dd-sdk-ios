/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Interface that allows filtering of the events before they are sent
/// to the server.
public protocol EventsFilter {
    /// Filters the events.
    /// - Parameter events: The events to be filtered.
    /// - Returns: The filtered events.
    func filter(events: [Event]) -> [Event]
}

/// Struct representing a single event.
public struct Event: Equatable {
    /// Data representing the event.
    public let data: Data

    /// Metadata associated with the event.
    /// Metadata is optional and may be `nil` but of very small size.
    /// This allows us to skip resource intensive operations in case such
    /// as filtering of the events.
    public let metadata: Data?

    public init(data: Data, metadata: Data?) {
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

        // otherwise, the next block is metadata
        let metadata = dataBlocks[index]
        index += 1

        return Event(data: event.data, metadata: metadata.data)
    }
}

extension RUMViewEvent {
    /// Metadata associated with the `RUMViewEvent`.
    /// It may be used to filter out the `RUMViewEvent` from the batch.
    struct Metadata: Codable {
        let id: String
        let documentVersion: Int64

        private enum CodingKeys: String, CodingKey {
            case id = "id"
            case documentVersion = "document_version"
        }
    }

    /// Creates `Metadata` from the given `RUMViewEvent`.
    /// - Returns: The `Metadata` for the given `RUMViewEvent`.
    func metadata() -> Metadata {
        return Metadata(id: view.id, documentVersion: dd.documentVersion)
    }
}
