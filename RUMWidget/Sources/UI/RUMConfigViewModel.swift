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
    @Published var isSDKEnabled: Bool = Datadog.isInitialized()
    @Published var isLogsEnabled: Bool = true
    @Published var isTracesEnabled: Bool = true
    @Published var isRUMEnabled: Bool = true
    @Published var isSessionReplayEnabled: Bool = true

    public enum Feature: String, CaseIterable {
        case logs = "Logs"
        case traces = "Traces"
        case rum = "RUM"
        case sessionReplay = "Session Replay"
    }

    public init() {
    }

    func toggle(feature: Feature) {
        guard !isSDKEnabled else { return }

        switch feature {
        case .logs:
            isLogsEnabled.toggle()
        case .traces:
            isTracesEnabled.toggle()
        case .rum:
            isRUMEnabled = true
        case .sessionReplay:
            isSessionReplayEnabled.toggle()
        }
    }

    func updateSDK(feature: RUMWidgetFeature) {

        isSDKEnabled
        ? feature.stopSDK()
        : feature.startSDK(
            isRUMEnabled: isRUMEnabled,
            isLogsEnabled: isLogsEnabled,
            isTracesEnabled: isTracesEnabled,
            isSessionReplayEnabled: isSessionReplayEnabled
        )
        isSDKEnabled = Datadog.isInitialized()
    }
}
