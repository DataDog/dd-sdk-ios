/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct Vital: Encodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case name = "name"
        case start = "start_ns"
        case duration = "duration_ns"
    }
    /// UUID of the vital
    public let id: String
    /// Name of the vital
    public let name: String
    /// Operation key of the vital
    public let operationKey: String?
    /// Step type of the vital ["start", "end"]
    public let stepType: RUMVitalOperationStepEvent.Vital.StepType?
    /// Date when the vital was created
    public let date: Date
    /// Duration of the vital in nanoseconds
    public let duration: Int64
    /// Key identifier of the vital
    public let key: String

    public init(
        id: String,
        name: String,
        operationKey: String? = nil,
        stepType: RUMVitalOperationStepEvent.Vital.StepType? = nil,
        date: Date = Date(),
        duration: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.operationKey = operationKey
        self.stepType = stepType
        self.date = date
        self.duration = duration
        self.key = "\(name)-\(operationKey ?? "")"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        let start = date.timeIntervalSince1970.dd.toInt64Nanoseconds
        try container.encode(start, forKey: .start)
        try container.encode(duration, forKey: .duration)
    }
}
