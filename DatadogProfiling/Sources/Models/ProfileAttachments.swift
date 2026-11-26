/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@preconcurrency import DatadogInternal

internal struct PprofAttachment: Codable, Sendable {
    let filename: String
    let data: Data
}

/// Bundles all attachments that are part of a profile event.
internal struct ProfileAttachments: Codable {
    internal enum Constants {
        static let profileEventFilename: String = "event.json"
        static let rumEventsFilename: String = "rum-mobile-events.json"
        static let pprofFilename: String = "profile.pprof"
        static let heapPprofFilename: String = "heap.pprof"
    }

    let pprofs: [PprofAttachment]
    let rumEvents: Data

    init(pprofs: [PprofAttachment], rumEvents: Data) {
        self.pprofs = pprofs
        self.rumEvents = rumEvents
    }

    private enum CodingKeys: String, CodingKey {
        case pprofs
        case pprof
        case rumEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let pprofs = try container.decodeIfPresent([PprofAttachment].self, forKey: .pprofs) {
            self.pprofs = pprofs
        } else {
            // Profiles already persisted on disk used a single unnamed CPU attachment.
            self.pprofs = [.init(filename: Constants.pprofFilename, data: try container.decode(Data.self, forKey: .pprof))]
        }
        self.rumEvents = try container.decode(Data.self, forKey: .rumEvents)
        guard let events = try? JSONSerialization.jsonObject(with: rumEvents) as? [Any], !events.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .rumEvents,
                in: container,
                debugDescription: "Profile requires at least one RUM event"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pprofs, forKey: .pprofs)
        try container.encode(rumEvents, forKey: .rumEvents)
    }
}

/// Bundles individually all RUM events that are part of a profile event.
internal enum RUMEvent: Sendable {
    case vital(Vital)
    case error(DurationEvent)
    case longTask(DurationEvent)
}

extension RUMEvent: Encodable {
    func encode(to encoder: Encoder) throws {
        switch self {
        case .vital(let value):
            try value.encode(to: encoder)
        case .error(let value):
            try value.encode(to: encoder)
        case .longTask(let value):
            try value.encode(to: encoder)
        }
    }
}
