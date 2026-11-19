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
    var legacyWebViewTrackingReceipt: RUMLegacyWebViewTrackingReceipt? { get }
    func activateRUMContextHandoff() throws -> RUMContextHandoff.Owner
    func deactivateRUMContextHandoff(owner: RUMContextHandoff.Owner)
    func registerRUMContextHandoff<T>(feature: T, owner: RUMContextHandoff.Owner) throws where T: DatadogFeature
}

@_spi(Internal)
public extension RUMContextHandoffActivating {
    var legacyWebViewTrackingReceipt: RUMLegacyWebViewTrackingReceipt? { nil }
}

/// Receives activation directly, independently of asynchronous context messages.
@_spi(Internal)
public protocol RUMContextHandoffReceiving: AnyObject {
    func receiveRUMContextHandoff(owner: RUMContextHandoff.Owner, active: Bool)
}

/// Optional owner-conditional RUM context publication; ordinary scopes are unchanged.
@_spi(Internal)
public protocol RUMContextHandoffContextUpdating {
    func setRUMContext(for owner: RUMContextHandoff.Owner, context: @escaping () -> RUMContextHandoff.ContextUpdate)
}

/// Optional built-in delivery capability; custom scopes retain ordinary Flags delivery.
@_spi(Internal)
public protocol RUMFlagEvaluationSending {
    func dispatchFlagEvaluation(_ evaluation: RUMFlagEvaluationMessage)
}

@_spi(Internal)
public extension FeatureScope {
    func sendFlagEvaluation(_ evaluation: RUMFlagEvaluationMessage) {
        if let scope = self as? RUMFlagEvaluationSending {
            scope.dispatchFlagEvaluation(evaluation)
        } else {
            send(message: .payload(evaluation))
        }
    }
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
    /// Rejection is distinct from an accepted update that clears RUM context.
    public enum ContextUpdate {
        case skip
        case set(RUMCoreContext?)
    }

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
        private struct View: Equatable {
            let sessionID: String
            let viewID: String
        }

        private enum State {
            case pending
            case restoring(View)
            case accepted(String)
            case acceptedRestoration(View)
            case rejected
        }

        public let owner: Owner
        private let sessionID: String?
        private let viewID: String?
        private let rolloverSource: View?
        @ReadWriteLock
        private var state = State.pending

        public init(owner: Owner, context: RUMCoreContext?, rolloverSource: RUMCoreContext? = nil) {
            self.owner = owner
            self.sessionID = context?.sessionID
            self.viewID = context?.viewID
            self.rolloverSource = rolloverSource.flatMap { context in
                context.viewID.map { View(sessionID: context.sessionID, viewID: $0) }
            }
        }

        public var hasCapturedView: Bool { viewID != nil }

        public var canAcceptRestoredView: Bool { rolloverSource != nil }

        public func matchesView(sessionID: String, viewID: String) -> Bool {
            self.sessionID == sessionID && self.viewID == viewID
        }

        /// Allows a tap that triggered rollover to settle only on its own restored view.
        public func prepareRestoredView(fromSessionID: String, fromViewID: String, sessionID: String, viewID: String) {
            guard rolloverSource == View(sessionID: fromSessionID, viewID: fromViewID) else {
                return
            }
            _state.mutate { state in
                guard owner.isValid, case .pending = state else {
                    return
                }
                state = .restoring(View(sessionID: sessionID, viewID: viewID))
            }
        }

        public func restoredView(for owner: Owner) -> (sessionID: String, viewID: String)? {
            guard self.owner === owner, owner.isValid, case let .acceptedRestoration(view) = state else {
                return nil
            }
            return (view.sessionID, view.viewID)
        }

        /// Called only when processing creates this command's action scope.
        public func accept(sessionID: String, viewID: String, actionID: String) {
            _state.mutate { state in
                switch state {
                case .pending:
                    state = owner.isValid && matchesView(sessionID: sessionID, viewID: viewID) ? .accepted(actionID) : .rejected
                case .restoring(let view):
                    state = owner.isValid && view == View(sessionID: sessionID, viewID: viewID) ? .acceptedRestoration(view) : .rejected
                case .accepted, .acceptedRestoration, .rejected:
                    break
                }
            }
        }

        /// Known drops or completed resolved processing settle only an unclaimed command.
        public func reject() {
            _state.mutate { state in
                switch state {
                case .pending, .restoring:
                    state = .rejected
                case .accepted, .acceptedRestoration, .rejected:
                    break
                }
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

    private final class UIKitDelivery: @unchecked Sendable {
        weak var event: AnyObject?
        @ReadWriteLock
        var isOpen = true

        init(event: AnyObject) {
            self.event = event
        }
    }

    private struct Scope: Sendable {
        let primary: Binding
        let peers: [ObjectIdentifier: Binding]
        let delivery: UIKitDelivery?
    }

    @TaskLocal private static var scope: Scope?

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
        guard supportsExecutionScope, let owner, owner.isValid, let scope else {
            return nil
        }
        if scope.primary.owner === owner {
            return scope.primary.value
        }
        return scope.peers[ObjectIdentifier(owner)]?.value
    }

    /// Keeps a retired owner or inherited binding authoritative for an On consumer.
    /// An unbound call or a different live owner's binding uses the receiver's normal path.
    public static func captureValue(for owner: Owner?) -> CurrentValue? {
        guard supportsExecutionScope, let owner else {
            return nil
        }
        if let value = current(for: owner) {
            return value
        }
        guard !owner.isValid || scope?.primary.owner.isValid == false else {
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
        let scope = Scope(primary: Binding(owner: owner, value: value), peers: [:], delivery: nil)
        return try $scope.withValue(scope, operation: operation)
    }

    /// Composes SDK wrappers while UIKit delivers the same event to the app.
    /// Child tasks inherit the captured values. Later deliveries open a fresh scope.
    public static func withUIKitDeliveryValue<T>(
        _ value: CurrentValue,
        for owner: Owner,
        event: AnyObject,
        operation: () throws -> T
    ) rethrows -> T {
        guard supportsExecutionScope, owner.isValid else {
            return try operation()
        }
        let primary = Binding(owner: owner, value: value)
        if let scope, let delivery = scope.delivery, delivery.isOpen, delivery.event === event {
            var peers = scope.peers
            if scope.primary.owner !== owner {
                peers[ObjectIdentifier(scope.primary.owner)] = scope.primary
            }
            peers.removeValue(forKey: ObjectIdentifier(owner))
            return try $scope.withValue(Scope(primary: primary, peers: peers, delivery: delivery), operation: operation)
        }
        let delivery = UIKitDelivery(event: event)
        defer { delivery.isOpen = false }
        return try $scope.withValue(Scope(primary: primary, peers: [:], delivery: delivery), operation: operation)
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
        let scope = Scope(primary: Binding(owner: owner, value: value), peers: [:], delivery: nil)
        return try await $scope.withValue(scope, operation: operation, isolation: isolation)
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

/// Provides a snapshot only after a caller independently proves the originating native scene.
@_spi(Internal)
public protocol RUMContextHandoffWebViewProviding {
    var usesLegacyWebViewTracking: Bool { get }
    func captureRUMContext(forSceneIdentifier sceneIdentifier: String, owner: RUMContextHandoff.Owner) -> RUMContextHandoff.Capture?
}

@_spi(Internal)
public extension RUMContextHandoffWebViewProviding {
    var usesLegacyWebViewTracking: Bool { false }
}

/// Validates a captured native session against the current RUM lifetime.
@_spi(Internal)
public protocol RUMContextHandoffSessionValidating {
    func isRUMContextHandoffSessionActive(sessionID: String, owner: RUMContextHandoff.Owner) -> Bool
}

/// Identifies the committed legacy RUM registration that received a Browser callback.
@_spi(Internal)
public struct RUMLegacyWebViewTrackingReceipt {
    private let isRegistrationCurrent: () -> Bool
    private let updateRUMContext: (@escaping () -> RUMCoreContext?) -> Void

    public init(isCurrent: @escaping () -> Bool, setRUMContext: @escaping (@escaping () -> RUMCoreContext?) -> Void) {
        self.isRegistrationCurrent = isCurrent
        self.updateRUMContext = setRUMContext
    }

    public var isCurrent: Bool { isRegistrationCurrent() }

    public func setRUMContext(_ context: @escaping () -> RUMCoreContext?) {
        updateRUMContext(context)
    }
}

@_spi(Internal)
public struct WebViewMessageWithLegacyRUMRegistration {
    public let message: WebViewMessage
    public let receipt: RUMLegacyWebViewTrackingReceipt

    public init(message: WebViewMessage, receipt: RUMLegacyWebViewTrackingReceipt) {
        self.message = message
        self.receipt = receipt
    }
}

/// Carries native ownership with a Browser message across asynchronous queues.
@_spi(Internal)
public struct WebViewMessageWithRUMContext {
    public let message: WebViewMessage
    public let capture: RUMContextHandoff.Capture

    public init(message: WebViewMessage, capture: RUMContextHandoff.Capture) {
        self.message = message
        self.capture = capture
    }

    /// Resolves only its original owner and a native session that is still alive at delivery.
    public func rumContext(in core: DatadogCoreProtocol, sessionID: String?) -> RUMCoreContext? {
        guard let owner = RUMContextHandoff.owner(in: core),
              owner === capture.owner, owner.isValid,
              let context = capture.value.resolvedRUMContext(for: owner),
              context.sessionID == sessionID,
              let validator = core.feature(named: Feature.rum, type: RUMContextHandoffSessionValidating.self),
              validator.isRUMContextHandoffSessionActive(sessionID: context.sessionID, owner: owner) else {
            return nil
        }
        return context
    }
}
