/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct DurationEvent: Encodable, Equatable {
    public enum EventType: String, Encodable {
        case longTask = "long_task"
        case error
    }
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case start = "start_ns"
        case duration = "duration_ns"
    }
    /// UUID of the event
    public let id: String
    /// Type of the event
    public let type: EventType
    /// Start of the event from epoch in nanoseconds
    public let start: Int64
    /// Duration of the event in nanoseconds
    public let duration: Int64

    public init(
        id: String,
        type: EventType,
        start: Int64,
        duration: Int64
    ) {
        self.id = id
        self.type = type
        self.start = start
        self.duration = duration
    }
}
