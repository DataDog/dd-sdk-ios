/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Provides an optional lifetime token without requiring custom or NOP scopes to conform.
@_spi(Internal)
public protocol RUMContextHandoffOwnerProviding {
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { get }
}

/// Synchronous activation capability implemented by the built-in Core only.
/// Custom and NOP cores need not implement this SPI.
@_spi(Internal)
public protocol RUMContextHandoffActivating: RUMContextHandoffOwnerProviding {
    func activateRUMContextHandoff() throws -> RUMContextHandoff.Owner
    func deactivateRUMContextHandoff(owner: RUMContextHandoff.Owner)
    func registerRUMContextHandoff<T>(feature: T, owner: RUMContextHandoff.Owner) throws where T: DatadogFeature
}

/// Receives activation directly, independently of asynchronous context messages.
@_spi(Internal)
public protocol RUMContextHandoffReceiving: AnyObject {
    func receiveRUMContextHandoff(owner: RUMContextHandoff.Owner, active: Bool)
}

/// Optional built-in write capability; custom and NOP scopes keep their original method.
@_spi(Internal)
public protocol RUMContextHandoffEventWriting {
    func eventWriteContextWithRUMCapture(
        bypassConsent: Bool,
        _ block: @escaping (DatadogContext, Writer, RUMContextHandoff.Capture?) -> Void
    )
}

@_spi(Internal)
public extension FeatureScope {
    func eventWriteContextWithRUMCapture(
        _ block: @escaping (DatadogContext, Writer, RUMContextHandoff.Capture?) -> Void
    ) {
        if let scope = self as? RUMContextHandoffEventWriting {
            scope.eventWriteContextWithRUMCapture(bypassConsent: false, block)
        } else {
            eventWriteContext { context, writer in
                block(context, writer, nil)
            }
        }
    }
}

/// Declares request-local ownership; activation is supplied by the scene input layer.
@_spi(Internal)
public enum RUMContextHandoff {
    /// A lifetime token that retains no core, feature or UI object.
    public final class Owner: @unchecked Sendable {
        @ReadWriteLock
        private var isActive = true

        public init() {}

        public func invalidate() {
            isActive = false
        }

        public var isValid: Bool { isActive }
    }

    /// Acceptance of one submitted action; no Core, feature or UI object is retained.
    public final class ActionReceipt: @unchecked Sendable {
        private enum State {
            case pending
            case accepted(String)
            case rejected
        }

        public let owner: Owner
        private let sessionID: String?
        private let viewID: String?
        @ReadWriteLock
        private var state = State.pending

        public init(owner: Owner, context: RUMCoreContext?) {
            self.owner = owner
            self.sessionID = context?.sessionID
            self.viewID = context?.viewID
        }

        /// Called only when processing creates this command's action scope.
        public func accept(sessionID: String, viewID: String, actionID: String) {
            _state.mutate { state in
                guard case .pending = state else {
                    return
                }
                guard owner.isValid, self.sessionID == sessionID, self.viewID == viewID else {
                    state = .rejected
                    return
                }
                state = .accepted(actionID)
            }
        }

        /// Known drops or completed resolved processing settle only an unclaimed command.
        public func reject() {
            _state.mutate { state in
                if case .pending = state { state = .rejected }
            }
        }

        /// An unresolved command cannot borrow an action from subsequent delivery context.
        public func actionID(for owner: Owner, sessionID: String, viewID: String?) -> String? {
            guard self.owner === owner, owner.isValid,
                  self.sessionID == sessionID, self.viewID == viewID else { return nil }
            guard case let .accepted(actionID) = state else {
                return nil
            }
            return actionID
        }
    }

    public struct CurrentValue {
        public let rumContext: RUMCoreContext?
        public let sceneIdentifier: String?
        public let hasPendingUserAction: Bool
        public let excludedUserActionID: String?
        public let actionReceipt: ActionReceipt?

        public init(
            rumContext: RUMCoreContext?,
            sceneIdentifier: String?,
            hasPendingUserAction: Bool,
            excludedUserActionID: String?,
            actionReceipt: ActionReceipt? = nil
        ) {
            self.rumContext = rumContext
            self.sceneIdentifier = sceneIdentifier
            self.hasPendingUserAction = hasPendingUserAction
            self.excludedUserActionID = excludedUserActionID
            self.actionReceipt = actionReceipt
        }

        /// Resolves only this captured action while preserving the captured RUM view.
        public func resolvedRUMContext(for owner: Owner) -> RUMCoreContext? {
            guard owner.isValid, let context = rumContext else {
                return nil
            }
            let actionID: String?
            if let actionReceipt {
                actionID = actionReceipt.actionID(for: owner, sessionID: context.sessionID, viewID: context.viewID)
            } else if hasPendingUserAction {
                actionID = nil
            } else {
                actionID = context.userActionID
            }
            return RUMCoreContext(
                applicationID: context.applicationID,
                sessionID: context.sessionID,
                sessionSampler: context.sessionSampler,
                viewID: context.viewID,
                userActionID: actionID,
                viewServerTimeOffset: context.viewServerTimeOffset,
                viewPath: context.viewPath,
                viewName: context.viewName
            )
        }
    }

    // The binding stores scalar context and a separately synchronized action receipt.
    // RUMCoreContext has an immutable Sendable sampler, but does not declare Sendable.
    private struct Binding: @unchecked Sendable {
        let owner: Owner
        let value: CurrentValue
    }

    @TaskLocal private static var binding: Binding?

    private static var supportsExecutionScope: Bool {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    /// Looks up only the current binding for the exact valid Core lifetime.
    /// A returned value with nil RUM context remains an authoritative override.
    public static func current(for owner: Owner?) -> CurrentValue? {
        guard supportsExecutionScope, let owner = owner, owner.isValid,
              let binding = binding, binding.owner === owner else {
            return nil
        }
        return binding.value
    }

    /// Captures an On consumer without turning an invalid retained owner into legacy fallback.
    /// A valid owner without a binding and unsupported systems retain the original path.
    public static func captureValue(for owner: Owner?) -> CurrentValue? {
        guard supportsExecutionScope, let owner else {
            return nil
        }
        if let value = current(for: owner) {
            return value
        }
        guard !owner.isValid else {
            return nil
        }
        return CurrentValue(
            rumContext: nil,
            sceneIdentifier: nil,
            hasPendingUserAction: false,
            excludedUserActionID: nil
        )
    }

    /// Binds a synchronous operation and restores the prior binding on return or throw.
    /// Unsupported systems and absent or invalid owners execute the operation directly.
    /// This primitive does not authorize automatic customer-callback integration.
    public static func withValue<T>(
        _ value: CurrentValue,
        for owner: Owner?,
        operation: () throws -> T
    ) rethrows -> T {
        guard supportsExecutionScope, let owner = owner, owner.isValid else {
            return try operation()
        }
        return try $binding.withValue(Binding(owner: owner, value: value), operation: operation)
    }

    /// Binds an asynchronous operation using the caller's isolation and restores the prior binding.
    /// Unsupported systems and absent or invalid owners execute the operation directly.
    /// Automatic customer-callback integration requires separate qualification.
    public static func withValue<T>(
        _ value: CurrentValue,
        for owner: Owner?,
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws -> T
    ) async rethrows -> T {
        guard supportsExecutionScope, let owner = owner, owner.isValid else {
            return try await operation()
        }
        return try await $binding.withValue(Binding(owner: owner, value: value), operation: operation, isolation: isolation)
    }

    public static func owner(in scope: Any) -> Owner? {
        (scope as? RUMContextHandoffOwnerProviding)?.rumContextHandoffOwner
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
    @_spi(Internal)
    public var rumURLSessionContext: RUMURLSessionContext? = nil
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
