/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// An entry point to Datadog Session Replay feature.
@objc(DDSessionReplay)
public final class SessionReplay: NSObject {
    public typealias Configuration = SessionReplayConfiguration

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
        with configuration: SessionReplay.Configuration, in core: DatadogCoreProtocol
    ) {
        do {
            try enableOrThrow(with: configuration, in: core)
        } catch let error {
           consolePrint("\(error)")
       }
    }

    /// Enables Datadog Session Replay feature.
    ///
    /// Recording will start automatically after enabling Session Replay.
    ///
    /// Note: Session Replay requires the RUM feature to be enabled.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    @objc
    public static func enable(with configuration: SessionReplay.Configuration) {
        enable(with: configuration, in: CoreRegistry.default)
    }

    internal static func enableOrThrow(
        with configuration: SessionReplay.Configuration, in core: DatadogCoreProtocol
    ) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `SessionReplay.enable(with:)`."
            )
        }

        let sampleRate = configuration.debugSDK ? 100 : configuration.replaySampleRate

        let sessionReplay = try SessionReplayFeature(
            core: core,
            sampleRate: sampleRate,
            privacy: configuration.defaultPrivacyLevel,
            customEndpoint: configuration.customEndpoint
        )

        try core.register(feature: sessionReplay)
        sessionReplay.writer.startWriting(to: core)
    }

    override private init() {
        super.init()
    }
}
