/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class ConfigurationReceiver: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: any DatadogCoreProtocol) -> Bool {
        guard
            case let .configuration(configuration) = message,
            let config = configuration.property(ConfigurationFile.self, forKey: "sr"),
            let sr = core.get(feature: SessionReplayFeature.self)
        else {
            return false
        }

        if let privacy = config.defaultPrivacyLevel {
            sr.recordingCoordinator.privacy = privacy
        }

        return true
    }
}
