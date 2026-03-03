/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Bundles all attachments that are part of a profile event.
internal struct ProfileAttachments: Codable {
    internal enum Constants {
        static let profileEventFilename: String = "event.json"
        static let rumEventsFilename: String = "rum-mobile-events.json"
        static let wallFilename: String = "wall.pprof"
    }

    let pprof: Data
    let rumEvents: Data?
}

/// Bundles all RUM events that are part of a profile event.
internal struct RUMEvents: Codable, Equatable {
    let vitals: [Vital]
}
