/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The slice of the core context Trace keeps between messages.
///
/// The RUM session is deliberately NOT here. It used to be, and the sampling decision was taken from
/// it, which is what made requests instrumented before the first `.context` message land fall back to
/// random sampling. Sampling now reads ``RUMSessionSamplerProvider`` on the calling thread; do not
/// re-introduce a bus-lagged copy of the RUM identity in this struct. See RUM-17921.
internal struct CoreContext {
    /// Provides the history of app foreground / background states.
    var applicationStateHistory: AppStateHistory?

    /// Provides the current user information, if any
    var userInfo: UserInfo?

    /// Provides the current account information, if any
    var accountInfo: AccountInfo?
}

internal final class ContextMessageReceiver: FeatureMessageReceiver {
    /// Creates a new `ContextMessageReceiver`.
    init() {
        self.context = .init()
    }

    /// The up-to-date core context.
    ///
    /// The context is synchronized using a read-write lock.
    @ReadWriteLock
    var context: CoreContext

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
        _context.mutate {
            $0.applicationStateHistory = datadogContext.applicationStateHistory
            $0.userInfo = datadogContext.userInfo
            $0.accountInfo = datadogContext.accountInfo
        }

        return true
    }
}
