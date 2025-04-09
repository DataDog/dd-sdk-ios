/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
import DatadogInternal
import DatadogLogs
import DatadogRUM
import DatadogSessionReplay
import DatadogTrace
import Foundation

@available(iOS 15.0, *)
public final class RUMConfigViewModel: ObservableObject {
    @Published var isSDKEnabled: Bool
    @Published var isLogsEnabled: Bool = false
    @Published var isTracesEnabled: Bool = false
    @Published var isRUMEnabled: Bool = false
    @Published var isSessionReplayEnabled: Bool = false

    public enum Feature: String, CaseIterable {
        case logs = "Logs"
        case traces = "Traces"
        case rum = "RUM"
        case sessionReplay = "Session Replay"
    }

    private let core: DatadogCoreProtocol

    private var sdkConfig: Datadog.Configuration?
//    private var logsConfig: Logs.Configuration?
//    private var tracesConfig: Trace.Configuration?
    private var rumConfig: RUM.Configuration?
    private var sessionReplayConfig: SessionReplay.Configuration?

    public init(
        core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        self.core = core
        isSDKEnabled = Datadog.isInitialized()

        sdkConfig = nil // FIXME: Where do we retrieve the config

        rumConfig = nil
        sessionReplayConfig = nil

        isLogsEnabled = false
        isRUMEnabled = false
        isTracesEnabled = false
        isSessionReplayEnabled = false
    }

    func stopSdk() {
        Datadog.stopInstance()
        isSDKEnabled = false
    }

    func startSdk() {
        do {
            guard let sdkConfig else { return }

            Datadog.initialize(
                with: sdkConfig,
                trackingConsent: .granted
            )

            if isLogsEnabled {
                Logs.enable()
            }

            if isTracesEnabled {
                Trace.enable()
            }

            if isRUMEnabled, let rumConfig {
                RUM.enable(with: rumConfig)
            }

            if isSessionReplayEnabled, let sessionReplayConfig {
                SessionReplay.enable(with: sessionReplayConfig)
            }

            isSDKEnabled = true
        } catch {
            print("Failed to initialize SDK: \(error)")
        }
    }

    func toggleFeature(_ feature: Feature) {
        guard !isSDKEnabled else { return }
        switch feature {
        case .logs:
            isLogsEnabled.toggle()
        case .traces:
            isTracesEnabled.toggle()
        case .rum:
            isRUMEnabled.toggle()
        case .sessionReplay:
            isSessionReplayEnabled.toggle()
        }
    }
}
