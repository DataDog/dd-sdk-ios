/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

extension SessionReplay.Configuration {
    /// Merges the remote configuration on top of this in-code configuration.
    ///
    /// The `sessionReplay` namespace overrides the supported behavioral parameters: sample rate, the
    /// three privacy levels, and whether recording starts immediately. Remote values take precedence,
    /// while any parameter the remote configuration omits keeps its in-code value; passing `nil` (no
    /// remote configuration was fetched) therefore leaves the configuration entirely unchanged.
    ///
    /// The merge happens once, at `SessionReplay.enable(with:)` time; live updates after initialization
    /// are out of scope.
    ///
    /// - Parameter remoteConfiguration: The remote configuration to merge, or `nil` when none is
    ///   available (leaving this configuration unchanged).
    mutating func apply(remoteConfiguration: RemoteConfiguration?) {
        apply(sessionReplay: remoteConfiguration?.sessionReplay)
    }

    /// Applies the `sessionReplay` namespace, overriding the supported behavioral parameters with their
    /// remote values.
    ///
    /// Scalar and enum settings are overridden directly; the privacy enums are translated from their
    /// remote representation to the in-code one. A missing field leaves the in-code value untouched.
    ///
    /// - Parameter sessionReplay: The `sessionReplay` namespace, or `nil` to leave the configuration
    ///   unchanged.
    private mutating func apply(sessionReplay: RemoteConfiguration.SessionReplay?) {
        guard let sessionReplay else {
            return
        }

        override(\.replaySampleRate, with: sessionReplay.sampleRate.map { SampleRate($0) })
        override(\.startRecordingImmediately, with: sessionReplay.startRecordingImmediately)
        override(\.textAndInputPrivacyLevel, with: sessionReplay.textAndInputPrivacy.map { TextAndInputPrivacyLevel($0) })
        override(\.imagePrivacyLevel, with: sessionReplay.imagePrivacy.map { ImagePrivacyLevel($0) })
        override(\.touchPrivacyLevel, with: sessionReplay.touchPrivacy.map { TouchPrivacyLevel($0) })
    }

    /// Overrides the value at `keyPath` with `remoteValue` when it is present.
    ///
    /// The merge primitive for a setting that maps one-to-one onto a stored property: a present remote
    /// value wins, an absent one (`nil`) leaves the in-code value untouched.
    ///
    /// - Parameters:
    ///   - keyPath: The configuration property to override.
    ///   - remoteValue: The remote value to apply, or `nil` when the remote configuration omits it.
    private mutating func override<Value>(_ keyPath: WritableKeyPath<Self, Value>, with remoteValue: Value?) {
        if let remoteValue {
            self[keyPath: keyPath] = remoteValue
        }
    }
}

private extension TextAndInputPrivacyLevel {
    /// Maps a remote text-and-input privacy level onto the in-code `TextAndInputPrivacyLevel`.
    ///
    /// - Parameter remote: The remote text-and-input privacy level.
    init(_ remote: RemoteConfiguration.SessionReplay.TextAndInputPrivacy) {
        switch remote {
        case .maskSensitiveInputs: self = .maskSensitiveInputs
        case .maskAllInputs: self = .maskAllInputs
        case .maskAll: self = .maskAll
        @unknown default: self = .maskAll
        }
    }
}

private extension ImagePrivacyLevel {
    /// Maps a remote image privacy level onto the in-code `ImagePrivacyLevel`.
    ///
    /// - Parameter remote: The remote image privacy level.
    init(_ remote: RemoteConfiguration.SessionReplay.ImagePrivacy) {
        switch remote {
        case .maskNone: self = .maskNone
        case .maskNonBundledOnly: self = .maskNonBundledOnly
        case .maskAll: self = .maskAll
        @unknown default: self = .maskAll
        }
    }
}

private extension TouchPrivacyLevel {
    /// Maps a remote touch privacy level onto the in-code `TouchPrivacyLevel`.
    ///
    /// - Parameter remote: The remote touch privacy level.
    init(_ remote: RemoteConfiguration.SessionReplay.TouchPrivacy) {
        switch remote {
        case .show: self = .show
        case .hide: self = .hide
        @unknown default: self = .hide
        }
    }
}

#endif
