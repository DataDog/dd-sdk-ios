/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

public struct Vital: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case name = "name"
        case start = "start_ns"
        case duration = "duration_ns"
    }
    /// UUID of the vital
    public let id: String
    /// Name of the Vital
    public let name: String
    /// Start of the vital from epoch in nanoseconds
    public let start: Int64
    /// Duration of the vital in nanoseconds
    public let duration: Int64

    public init(id: String, name: String, start: Int64, duration: Int64) {
        self.id = id
        self.name = name
        self.start = start
        self.duration = duration
    }
}
