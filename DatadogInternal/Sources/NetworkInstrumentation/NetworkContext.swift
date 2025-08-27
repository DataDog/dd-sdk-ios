/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Describes current Datadog SDK context, so the app state information can be attached to
/// instrumented Network traces.
public struct NetworkContext {
    /// Provides the current active RUM context, if any
    public var rumContext: RUMCoreContext?
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
