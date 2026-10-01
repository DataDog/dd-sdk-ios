/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// An immutable description of a flag client event.
///
/// This value does not emit events or change client readiness.
public struct FlagsClientEvent: Equatable {
    /// The kind of event.
    public let type: FlagsClientEventType

    /// A snapshot of affected flag keys, if supplied.
    ///
    /// `nil` means no keys were supplied; an empty array means an explicitly supplied empty list.
    public let flagsChanged: [String]?

    /// Creates a flag client event.
    ///
    /// Swift array value semantics isolate these keys from subsequent changes to the caller's array.
    /// No keys are inferred or evaluated.
    ///
    /// - Parameters:
    ///   - type: The kind of event.
    ///   - flagsChanged: Optional affected keys. Defaults to `nil`.
    public init(type: FlagsClientEventType, flagsChanged: [String]? = nil) {
        self.type = type
        self.flagsChanged = flagsChanged
    }
}

/// Flag client event kinds and their shared string representations.
public enum FlagsClientEventType: String {
    /// A flag configuration changed.
    case configurationChanged = "CONFIGURATION_CHANGED"
}
