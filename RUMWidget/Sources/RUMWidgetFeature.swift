/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogCore
import DatadogRUM
import DatadogSessionReplay
import DatadogLogs
import DatadogTrace


@available(iOS 13.0, *)
final class RUMWidgetFeature: DatadogFeature, ObservableObject {
    public static var name = "rum_widget"

    public var messageReceiver: FeatureMessageReceiver

    private let configuration: Datadog.Configuration

    private var rumConfiguration: RUM.Configuration?

    private let srConfiguration = SessionReplay.Configuration()

    init(
        in core: DatadogCoreProtocol,
        configuration: Datadog.Configuration
    ) throws {
        self.configuration = configuration
        self.messageReceiver = CombinedFeatureMessageReceiver([])

        if let rumFeature = CoreRegistry.default.get(feature: RUMFeature.self) {
            rumConfiguration = rumFeature.configuration
        }
    }
}

@available(iOS 13.0, *)
extension RUMWidgetFeature {
    func stopSDK() {
        Datadog.stopInstance()
    }

    func startSDK(
        isRUMEnabled: Bool = true,
        isLogsEnabled: Bool = true,
        isTracesEnabled: Bool = true,
        isSessionReplayEnabled: Bool = true
    ) {
        Datadog.initialize(
            with: configuration,
            trackingConsent: .granted
        )

        Datadog.verbosityLevel = .debug

        if isRUMEnabled, let rumConfiguration {
            RUM.enable(with: rumConfiguration)
        }

        if isLogsEnabled {
            Logs.enable()
        }

        if isTracesEnabled {
            Trace.enable()
        }

        if isSessionReplayEnabled  {
            SessionReplay.enable(with: srConfiguration)
        }
    }
}
