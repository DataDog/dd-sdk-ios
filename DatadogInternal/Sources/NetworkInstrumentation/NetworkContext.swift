/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Identifies the core lifetime shared by first-party feature scopes.
/// Custom and NOP scopes need not conform and receive no UI-event override.
@_spi(Internal)
public protocol RUMContextHandoffOwnerProviding {
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { get }
}

/// Request-local RUM context scoped to one SDK lifetime.
@_spi(Internal)
public enum RUMContextHandoff {
    /// An opaque core-generation token. It owns no core, feature or UI object.
    public final class Owner: @unchecked Sendable {
        @ReadWriteLock
        private var isActive = true

        public init() {}

        public func invalidate() {
            isActive = false
        }

        fileprivate var isValid: Bool { isActive }
    }

    public struct CurrentValue {
        public let rumContext: RUMCoreContext?
        public let sceneIdentifier: String?
        public let hasPendingUserAction: Bool
        public let excludedUserActionID: String?
    }

    private struct Value {
        let owner: Owner
        let rumContextProvider: () -> RUMCoreContext?
        let sceneIdentifier: String
        let hasPendingUserAction: Bool
        let excludedUserActionID: String?
    }

    private struct Snapshot {
        let owner: Owner
        let context: CurrentValue
    }

    /// One reusable cell per dispatching thread avoids boxing the RUM context
    /// into Foundation on every event. No owner or context survives scope exit.
    private final class ThreadState {
        var current: Snapshot?
        var outerOwners: [Snapshot] = []
    }

    private static let threadStateKey: NSString = "com.datadoghq.rum.ui-event-context-state"
    @TaskLocal private static var value: Value?
    @TaskLocal private static var outerOwners: [Value] = []

    public static func owner(in scope: Any) -> Owner? {
        (scope as? RUMContextHandoffOwnerProviding)?.rumContextHandoffOwner
    }

    public static func current(in scope: Any) -> CurrentValue? {
        current(for: owner(in: scope))
    }

    /// A present result with nil context is authoritative only for its owner.
    /// Synchronous dispatch uses its entry snapshot. Inherited tasks refresh the
    /// matching scene through the provider after the thread scope has unwound.
    public static func current(for owner: Owner?) -> CurrentValue? {
        guard let owner, owner.isValid else {
            return nil
        }
        if let state = Thread.current.threadDictionary[threadStateKey] as? ThreadState {
            if let current = state.current, current.owner === owner {
                return current.context
            }
            if let outer = state.outerOwners.last(where: { $0.owner === owner }) {
                return outer.context
            }
        }
        let matchingValue = value?.owner === owner
            ? value : outerOwners.last(where: { $0.owner === owner })
        guard let matchingValue else {
            return nil
        }
        return CurrentValue(
            rumContext: matchingValue.rumContextProvider(),
            sceneIdentifier: matchingValue.sceneIdentifier,
            hasPendingUserAction: matchingValue.hasPendingUserAction,
            excludedUserActionID: matchingValue.excludedUserActionID
        )
    }

    public static func withValue<T>(
        owner: Owner?,
        rumContext: RUMCoreContext?,
        sceneIdentifier: String,
        hasPendingUserAction: Bool = false,
        excludedUserActionID: String? = nil,
        operation: () throws -> T
    ) rethrows -> T {
        try withValue(
            owner: owner,
            rumContextProvider: { rumContext },
            sceneIdentifier: sceneIdentifier,
            hasPendingUserAction: hasPendingUserAction,
            excludedUserActionID: excludedUserActionID,
            operation: operation
        )
    }

    public static func withValue<T>(
        owner: Owner?,
        rumContextProvider: @escaping () -> RUMCoreContext?,
        sceneIdentifier: String,
        hasPendingUserAction: Bool = false,
        excludedUserActionID: String? = nil,
        operation: () throws -> T
    ) rethrows -> T {
        guard let owner, owner.isValid else {
            return try operation()
        }
        let next = Value(
            owner: owner,
            rumContextProvider: rumContextProvider,
            sceneIdentifier: sceneIdentifier,
            hasPendingUserAction: hasPendingUserAction,
            excludedUserActionID: excludedUserActionID
        )
        let dictionary = Thread.current.threadDictionary
        let state: ThreadState
        if let existing = dictionary[threadStateKey] as? ThreadState {
            state = existing
        } else {
            state = ThreadState()
            dictionary[threadStateKey] = state
        }
        let previous = state.current
        let hasForeignOwner = previous.map { $0.owner !== owner } ?? false
        if hasForeignOwner, let previous {
            state.outerOwners.append(previous)
        }
        state.current = Snapshot(
            owner: owner,
            context: CurrentValue(
                rumContext: rumContextProvider(),
                sceneIdentifier: sceneIdentifier,
                hasPendingUserAction: hasPendingUserAction,
                excludedUserActionID: excludedUserActionID
            )
        )
        defer {
            state.current = previous
            if hasForeignOwner {
                state.outerOwners.removeLast()
            }
        }
        if let value, value.owner !== owner {
            return try $outerOwners.withValue(outerOwners + [value]) {
                try $value.withValue(next, operation: operation)
            }
        }
        return try $value.withValue(next, operation: operation)
    }
}

/// Describes current Datadog SDK context, so the app state information can be attached to
/// instrumented Network traces.
public struct NetworkContext {
    /// Provides the current active RUM context, if any
    public var rumContext: RUMCoreContext?
    public var activeSpanProvider: TraceActiveSpanProvider?
    public var userConfigurationContext: UserConfigurationContext?
    public var accountConfigurationContext: AccountConfigurationContext?
}

/// The User configuration context received from `Core`.
public struct UserConfigurationContext: AdditionalContext, Equatable {
    /// User configuration key in core additional context.
    public static let key = "user_configuration"

    /// User anonymous ID, if configured.
    public let anonymousId: String?
    /// User ID, if any.
    public let id: String?
    /// Name representing the user, if any.
    public let name: String?
    /// User email, if any.
    public let email: String?

    /// Creates a User configuration context.
    ///
    /// - Parameters:
    ///   - anonymousId: User anonymous ID, if configured.
    ///   - id: User ID, if any.
    ///   - name: Name representing the user, if any.
    ///   - email: User email, if any.
    public init(
        anonymousId: String? = nil,
        id: String? = nil,
        name: String? = nil,
        email: String? = nil
    ) {
        self.anonymousId = anonymousId
        self.id = id
        self.name = name
        self.email = email
    }

    /// Creates a User configuration context from UserInfo.
    ///
    /// - Parameter userInfo: The UserInfo instance to create context from.
    public init(from userInfo: UserInfo) {
        self.anonymousId = userInfo.anonymousId
        self.id = userInfo.id
        self.name = userInfo.name
        self.email = userInfo.email
    }
}

/// The Account configuration context received from `Core`.
public struct AccountConfigurationContext: AdditionalContext, Equatable {
    /// Account configuration key in core additional context.
    public static let key = "account_configuration"

    /// Account ID
    public let id: String
    /// Name representing the account, if any.
    public let name: String?

    /// Creates an Account configuration context.
    ///
    /// - Parameters:
    ///   - id: Account ID
    ///   - name: Name representing the account, if any.
    public init(
        id: String,
        name: String? = nil
    ) {
        self.id = id
        self.name = name
    }

    /// Creates an Account configuration context from AccountInfo.
    ///
    /// - Parameter accountInfo: The AccountInfo instance to create context from.
    public init(from accountInfo: AccountInfo) {
        self.id = accountInfo.id
        self.name = accountInfo.name
    }
}
