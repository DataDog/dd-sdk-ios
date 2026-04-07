/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct DurationEvent: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case start = "start_ns"
        case duration = "duration_ns"
    }
    /// UUID of the event
    public let id: String
    /// Start of the event from epoch in nanoseconds
    public let start: Int64
    /// Duration of the event in nanoseconds
    public let duration: Int64

    public init(
        id: String,
        start: Int64,
        duration: Int64
    ) {
        self.id = id
        self.start = start
        self.duration = duration
    }
}
