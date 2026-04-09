/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct CoreContext {
    /// Provides the history of app foreground / background states.
    var applicationStateHistory: AppStateHistory?

    /// Provides the current active RUM context, if any
    var rumContext: RUMCoreContext?

    /// Provides the current user information, if any
    var userInfo: UserInfo?

    /// Provides the current account information, if any
    var accountInfo: AccountInfo?
}

internal final class ContextMessageReceiver: FeatureMessageReceiver {
    /// Creates a new `ContextMessageReceiver`.
    ///
    /// - parameters:
    ///   - samplerProvider: The sampler provider that will be updated with the RUM
    ///   deterministic tracer.
    init(samplerProvider: SamplerProvider) {
        self.samplerProvider = samplerProvider
        self.context = .init()
    }

    /// The up-to-date core context.
    ///
    /// The context is synchronized using a read-write lock.
    @ReadWriteLock
    var context: CoreContext

    /// The tracer sampler that should be updated with the RUM deterministic sampler.
    let samplerProvider: SamplerProvider

    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            return update(context: context, from: core)
        default:
            return false
        }
    }

    /// Updates context of the `DatadogTracer` if available.
    ///
    /// - Parameter context: The updated core context.
    private func update(context datadogContext: DatadogContext, from core: DatadogCoreProtocol) -> Bool {
        let rumContext = datadogContext.additionalContext(ofType: RUMCoreContext.self)

        _context.mutate {
            $0.applicationStateHistory = datadogContext.applicationStateHistory
            $0.rumContext = rumContext
            $0.userInfo = datadogContext.userInfo
            $0.accountInfo = datadogContext.accountInfo
        }

        samplerProvider.updateWith(deterministicSampler: rumContext?.sessionSampler)

        return true
    }
}
