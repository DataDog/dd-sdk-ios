/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An interface for writing and reading  the `NetworkContext`
internal protocol NetworkContextProvider: AnyObject {
    /// Returns current `NetworkContext` value.
    var currentNetworkContext: NetworkContext? { get }
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { get }
}

extension NetworkContextProvider {
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { nil }
}

/// Manages the `NetworkContext` reads and writes in a thread-safe manner.
internal class NetworkContextCoreProvider: NetworkContextProvider {
    // MARK: - NetworkContextProviderType
    private struct State {
        var context: NetworkContext?
        var owner: RUMContextHandoff.Owner?
    }

    @ReadWriteLock
    private var state = State()

    var currentNetworkContext: NetworkContext? {
        get { state.context }
        set { _state.mutate { $0.context = newValue } }
    }

    var rumContextHandoffOwner: RUMContextHandoff.Owner? {
        let owner = state.owner
        return owner?.isValid == true ? owner : nil
    }
}

extension NetworkContextCoreProvider: RUMContextHandoffReceiving {
    func receiveRUMContextHandoff(owner: RUMContextHandoff.Owner, active: Bool) {
        _state.mutate { state in
            if active {
                // A delayed publication cannot replace a newer lifetime: the old
                // owner is invalidated before the Core releases its registry lock.
                guard owner.isValid else {
                    return
                }
                state.owner = owner
            } else if state.owner === owner {
                // Rollback/stop clears only the lifetime it issued.
                state.owner = nil
            }
        }
    }
}

extension NetworkContextCoreProvider: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message else {
            return false
        }

        let userConfigurationContext: UserConfigurationContext? = {
            guard let userInfo = context.userInfo else {
                return nil
            }
            return UserConfigurationContext(from: userInfo)
        }()

        let accountConfigurationContext: AccountConfigurationContext? = {
            guard let accountInfo = context.accountInfo else {
                return nil
            }
            return AccountConfigurationContext(from: accountInfo)
        }()

        currentNetworkContext = NetworkContext(
            rumContext: context.additionalContext(ofType: RUMCoreContext.self),
            activeSpanProvider: context.additionalContext(ofType: TraceCoreContext.ActiveSpanProvider.self),
            userConfigurationContext: userConfigurationContext,
            accountConfigurationContext: accountConfigurationContext
        )
        return true
    }
}
