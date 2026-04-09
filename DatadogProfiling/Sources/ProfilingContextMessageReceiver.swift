/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

internal final class ProfilingContextMessageReceiver: FeatureMessageReceiver {
    let profilingSamplerProvider: ProfilingSamplerProvider

    init(profilingSamplerProvider: ProfilingSamplerProvider) {
        self.profilingSamplerProvider = profilingSamplerProvider
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message,
              let deterministicSampler = context.additionalContext(ofType: RUMCoreContext.self)?.sessionSampler else {
            return false
        }

        profilingSamplerProvider.updateWith(deterministicSampler: deterministicSampler)

        return false
    }
}
