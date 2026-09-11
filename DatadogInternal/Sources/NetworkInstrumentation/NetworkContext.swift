/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Request-local RUM context propagated through structured Swift tasks.
///
/// This is SPI because it only connects first-party SDK modules. The public
/// logging, tracing, and networking APIs do not expose or accept this value.
@_spi(Internal)
public enum RUMContextHandoff {
    public struct CurrentValue {
        public let rumContext: RUMCoreContext?
        public let sceneIdentifier: String?
        public let hasPendingUserAction: Bool
        public let excludedUserActionID: String?
    }

    private struct Value {
        let rumContextProvider: () -> RUMCoreContext?
        let sceneIdentifier: String
        let hasPendingUserAction: Bool
        let excludedUserActionID: String?
    }

    private static let rumContextKey = "\(String(reflecting: RUMCoreContext.self)).ui-event-network-context"
    private static let sceneIdentifierKey = "\(String(reflecting: RUMCoreContext.self)).ui-event-scene-identifier"
    private static let pendingUserActionKey = "\(String(reflecting: RUMCoreContext.self)).ui-event-pending-user-action"
    private static let excludedUserActionIDKey = "\(String(reflecting: RUMCoreContext.self)).ui-event-excluded-user-action-id"

    @TaskLocal private static var value: Value?

    /// Returns the synchronous thread override when present, otherwise the
    /// value inherited by the current structured Swift task. A non-nil result
    /// with a nil `rumContext` is intentional: the source scene is known but
    /// does not yet have a RUM view, so consumers must not use another scene's
    /// process-representative context.
    public static var current: CurrentValue? {
        let dictionary = Thread.current.threadDictionary
        if dictionary[rumContextKey] != nil {
            return CurrentValue(
                rumContext: dictionary[rumContextKey] as? RUMCoreContext,
                sceneIdentifier: dictionary[sceneIdentifierKey] as? String,
                hasPendingUserAction: dictionary[pendingUserActionKey] as? Bool == true,
                excludedUserActionID: dictionary[excludedUserActionIDKey] as? String
            )
        }
        guard let value else {
            return nil
        }
        return CurrentValue(
            rumContext: value.rumContextProvider(),
            sceneIdentifier: value.sceneIdentifier,
            hasPendingUserAction: value.hasPendingUserAction,
            excludedUserActionID: value.excludedUserActionID
        )
    }

    public static func withValue<T>(
        rumContext: RUMCoreContext?,
        sceneIdentifier: String,
        hasPendingUserAction: Bool = false,
        excludedUserActionID: String? = nil,
        operation: () throws -> T
    ) rethrows -> T {
        try withValue(
            rumContextProvider: { rumContext },
            sceneIdentifier: sceneIdentifier,
            hasPendingUserAction: hasPendingUserAction,
            excludedUserActionID: excludedUserActionID,
            operation: operation
        )
    }

    public static func withValue<T>(
        rumContextProvider: @escaping () -> RUMCoreContext?,
        sceneIdentifier: String,
        hasPendingUserAction: Bool = false,
        excludedUserActionID: String? = nil,
        operation: () throws -> T
    ) rethrows -> T {
        try $value.withValue(
            Value(
                rumContextProvider: rumContextProvider,
                sceneIdentifier: sceneIdentifier,
                hasPendingUserAction: hasPendingUserAction,
                excludedUserActionID: excludedUserActionID
            )
        ) {
            let dictionary = Thread.current.threadDictionary
            let previousContext = dictionary[rumContextKey]
            let previousSceneIdentifier = dictionary[sceneIdentifierKey]
            let previousPendingUserAction = dictionary[pendingUserActionKey]
            let previousExcludedUserActionID = dictionary[excludedUserActionIDKey]

            dictionary[rumContextKey] = rumContextProvider() ?? NSNull()
            dictionary[sceneIdentifierKey] = sceneIdentifier
            dictionary[pendingUserActionKey] = hasPendingUserAction
            dictionary[excludedUserActionIDKey] = excludedUserActionID ?? NSNull()
            defer {
                restore(previousContext, forKey: rumContextKey, in: dictionary)
                restore(previousSceneIdentifier, forKey: sceneIdentifierKey, in: dictionary)
                restore(previousPendingUserAction, forKey: pendingUserActionKey, in: dictionary)
                restore(previousExcludedUserActionID, forKey: excludedUserActionIDKey, in: dictionary)
            }
            return try operation()
        }
    }

    private static func restore(
        _ value: Any?,
        forKey key: String,
        in dictionary: NSMutableDictionary
    ) {
        if let value {
            dictionary[key] = value
        } else {
            dictionary.removeObject(forKey: key)
        }
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
