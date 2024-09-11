/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// An entry point to Datadog Session Replay feature.
public enum SessionReplay {
    /// Enables Datadog Session Replay feature.
    ///
    /// Recording will start automatically after enabling Session Replay.
    ///
    /// Note: Session Replay requires the RUM feature to be enabled.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    ///   - core: The instance of Datadog SDK to enable Session Replay in (global instance by default).
    public static func enable(
        with configuration: SessionReplay.Configuration,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            try enableOrThrow(with: configuration, in: core)
        } catch let error {
            consolePrint("\(error)", .error)
       }
    }

    /// Starts the recording manually.
    /// - Parameters:
    ///   - core: The instance of Datadog SDK to start Session Replay in (global instance by default).
    public static func startRecording(
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            try startRecording(core: core)
        } catch let error {
            consolePrint("\(error)", .error)
        }
    }

    /// Stops the recording manually.
    /// - Parameters:
    ///   - core: The instance of Datadog SDK to start Session Replay in (global instance by default).
    public static func stopRecording(
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            try stopRecording(core: core)
        } catch let error {
            consolePrint("\(error)", .error)
        }
    }

    // MARK: Internal

    internal static let maxObjectSize = 10.MB.asUInt64()

    internal static func enableOrThrow(
        with configuration: SessionReplay.Configuration,
        in core: DatadogCoreProtocol
    ) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `SessionReplay.enable(with:)`."
            )
        }
        guard configuration.replaySampleRate > 0 else {
            return
        }
        let resources = ResourcesFeature(core: core, configuration: configuration)
        try core.register(feature: resources)

        let sessionReplay = try SessionReplayFeature(core: core, configuration: configuration)
        try core.register(feature: sessionReplay)

        core.telemetry.configuration(
            defaultPrivacyLevel: configuration.defaultPrivacyLevel.rawValue,
            sessionReplaySampleRate: Int64(withNoOverflow: configuration.replaySampleRate),
            startRecordingImmediately: configuration.startRecordingImmediately
        )
    }

    internal static func startRecording(core: DatadogCoreProtocol) throws {
        guard let sr = core.get(feature: SessionReplayFeature.self) else {
            throw ProgrammerError(
                description: "Session Replay must be initialized before calling `SessionReplay.startRecording()`."
            )
        }

        sr.startRecording()
    }

    internal static func stopRecording(core: DatadogCoreProtocol) throws {
        let sr = core.get(feature: SessionReplayFeature.self)
        sr?.stopRecording()
    }
}
#endif
