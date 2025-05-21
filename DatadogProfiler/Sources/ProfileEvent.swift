/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct ProfileEvent: Codable {
    let start: Date
    let end: Date
    let cpuProf: Data
    /// The name of the service that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let service: String
    /// The version of the application that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let version: String
    /// Current RUM application ID - standard UUID string, lowercased.
    var applicationID: String?
    /// Current RUM session ID - standard UUID string, lowercased.
    var sessionID: String?
    /// Current RUM view ID - standard UUID string, lowercased. It can be empty when view is being loaded.
    var viewID: String?
}
