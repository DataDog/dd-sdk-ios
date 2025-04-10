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
    @Published var isLogsEnabled: Bool = true
    @Published var isTracesEnabled: Bool = true
    @Published var isRUMEnabled: Bool = true
    @Published var isSessionReplayEnabled: Bool = true

    public var configuration: Datadog.Configuration

    public enum Feature: String, CaseIterable {
        case logs = "Logs"
        case traces = "Traces"
        case rum = "RUM"
        case sessionReplay = "Session Replay"
    }

    private var rumConfig: RUM.Configuration?
    private var sessionReplayConfig: SessionReplay.Configuration?

    public init(
        configuration: Datadog.Configuration
    ) {
        self.configuration = configuration
        isSDKEnabled = Datadog.isInitialized()

        retrieveCurrentConfigurations()
    }

    private func retrieveCurrentConfigurations() {
        if let rumFeature = CoreRegistry.default.get(feature: RUMFeature.self) {
            rumConfig = rumFeature.configuration
        }

        sessionReplayConfig = SessionReplay.Configuration()
    }

    func stopSdk() {
        Datadog.stopInstance()
        isSDKEnabled = false
    }

    func startSdk() {
        do {
            Datadog.initialize(
                with: configuration,
                trackingConsent: .granted
            )

            Datadog.verbosityLevel = .debug // FIXME: remove debug mode

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
