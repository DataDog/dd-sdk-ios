/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// A notification from a feature flag client.
public struct FlagsClientEvent {
    /// The kind of notification.
    public let type: FlagsClientEventType
    /// Flag keys associated with the event. An empty array represents a valid empty configuration.
    public let flagsChanged: [String]?

    public init(type: FlagsClientEventType, flagsChanged: [String]? = nil) {
        self.type = type
        self.flagsChanged = flagsChanged
    }
}

/// Supported feature flag client notifications.
public enum FlagsClientEventType: String {
    case configurationChanged = "CONFIGURATION_CHANGED"
}
