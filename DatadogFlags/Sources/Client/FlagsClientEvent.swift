/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A native flag client notification. This does not imply OpenFeature readiness.
public struct FlagsClientEvent: Equatable {
    /// The kind of notification.
    public let type: FlagsClientEventType
    /// The provider that produced this notification.
    public let providerName: String
    /// Affected flag keys. For `onFirstFlags`, this is the complete first installed key set, including an empty set.
    public let flagsChanged: [String]?
    /// An optional description of the notification.
    public let message: String?
    /// An optional error classification.
    public let errorCode: FlagsClientErrorCode?
    /// Additional flat primitive metadata. Empty for `onFirstFlags`.
    public let metadata: [String: FlagsClientEventMetadataValue]
}

/// Event vocabulary shared by native flag clients. Only configuration changes are emitted by `onFirstFlags`.
public enum FlagsClientEventType: String {
    case configurationChanged = "CONFIGURATION_CHANGED"
    case ready = "READY"
    case error = "ERROR"
    case stale = "STALE"
    case reconciling = "RECONCILING"
    case contextChanged = "CONTEXT_CHANGED"
}

/// Error vocabulary used by flag client events, independent of an OpenFeature dependency.
public enum FlagsClientErrorCode: String {
    case providerNotReady = "PROVIDER_NOT_READY"
    case flagNotFound = "FLAG_NOT_FOUND"
    case parseError = "PARSE_ERROR"
    case typeMismatch = "TYPE_MISMATCH"
    case targetingKeyMissing = "TARGETING_KEY_MISSING"
    case invalidContext = "INVALID_CONTEXT"
    case providerFatal = "PROVIDER_FATAL"
    case general = "GENERAL"
}

/// Primitive values supported by event metadata.
public enum FlagsClientEventMetadataValue: Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
}
