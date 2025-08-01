/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct ProfileEvent: Encodable {
    internal enum Constants {
        static let eventFilename: String = "event.json"
        static let wallFilename: String = "wall.pprof"
    }

    /// The RUM Application
    internal struct Application: Encodable {
        /// The RUM Application ID
        let id: String
    }

    /// The RUM Session
    internal struct Session: Encodable {
        /// The RUM Session ID
        let id: String
    }

    /// The RUM Views.
    internal struct Views: Encodable {
        /// List of RUM View IDs
        let id: [String]
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
    /// The RUM Application
    var application: Application? = nil
    /// The RUM Session
    var session: Session? = nil
    /// The RUM Views.
    var view: Views? = nil
}
