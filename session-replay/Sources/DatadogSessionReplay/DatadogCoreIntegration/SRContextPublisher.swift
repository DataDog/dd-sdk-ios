/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

internal class SRContextPublisher {
    private weak var core: DatadogCoreProtocol?

    init(core: DatadogCoreProtocol) {
        self.core = core
    }

    /// Notifies other Features on the state of  Session Replay recording.
    func setRecordingIsPending(_ value: Bool) {
        let baggage: FeatureBaggage = [
            RUMDependency.hasReplay: value
        ]

        core?.set(feature: RUMDependency.srBaggageKey, attributes: { baggage })
    }
}
