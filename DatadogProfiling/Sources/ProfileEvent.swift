/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct ProfileEvent: Encodable {
    internal enum Constants {
        static let eventFilename: String = "event.json"
        static let wallFilename: String = "wall.pprof"
    }

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case attachments
        case tags = "tags_profiler"
        case family
        case runtime
        case version
    }

    /// The profile family.
    let family: String
    /// The profile runtime.
    let runtime: String
    /// The profiling version.
    let version: String
    /// Profile start date
    let start: Date
    /// Profile end date
    let end: Date
    /// The list of profiles attached to the event.
    let attachments: [String]
    /// The profile tags
    let tags: String
    /// The profile additional attributes, such a the RUM context.
    let additionalAttributes: [String: Encodable]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(tags, forKey: .tags)
        try container.encode(family, forKey: .family)
        try container.encode(runtime, forKey: .runtime)
        try container.encode(version, forKey: .version)

        var additionalContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try additionalAttributes?.forEach { key, value in
            try additionalContainer.encode(AnyEncodable(value), forKey: .init(key))
        }
    }
}
