/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@_spi(Internal)
public protocol RUMOperationOriginProviding: AnyObject {
    var operationOrigin: RUMOperationOrigin? { get }
    func isOperationMonitor(_ monitor: AnyObject) -> Bool
    func isOperationSessionActive(start: Date, lastInteraction: Date) -> Bool
}

@_spi(Internal)
public protocol RUMOperationFeatureRetiring: AnyObject {
    func retireOperationOrigin()
}

@_spi(Internal)
public protocol RUMOperationScopeProviding {
    func operationOrigin(for monitor: AnyObject) -> RUMOperationOrigin?
}

@_spi(Internal)
public protocol RUMOperationCancellationReceiving: AnyObject {
    func operationOwnershipDidRetire(_ ownership: RUMOperationOwnership)
}

/// Retains scalar Session state and weak original collaborators.
@_spi(Internal)
public final class RUMOperationOrigin: @unchecked Sendable {
    private struct State {
        var isRetired = false
        weak var feature: (any RUMOperationOriginProviding)?
        weak var monitor: AnyObject?
        var sessionID: String?
        var sessionStart: Date?
        var lastInteraction: Date?
        weak var ownership: RUMOperationOwnership?
    }

    public let owner: RUMContextHandoff.Owner
    private weak var core: (any DatadogCoreProtocol)?
    @ReadWriteLock private var state = State()

    public init(core: DatadogCoreProtocol, owner: RUMContextHandoff.Owner) {
        self.core = core
        self.owner = owner
    }

    /// Installed once after the original Feature has initialized.
    public func attach(feature: any RUMOperationOriginProviding, monitor: AnyObject) {
        _state.mutate {
            guard !$0.isRetired, $0.feature == nil, $0.monitor == nil else { return }
            $0.feature = feature
            $0.monitor = monitor
        }
    }

    public var isCurrent: Bool {
        let snapshot = state
        guard !snapshot.isRetired, owner.isValid, let core,
              let feature = snapshot.feature, let monitor = snapshot.monitor,
              feature.operationOrigin === self, feature.isOperationMonitor(monitor),
              let registered = core.feature(named: Feature.rum, type: RUMOperationOriginProviding.self),
              registered === feature else { return false }
        return true
    }

    /// Called at actual Session transition, independently of a profiler timer.
    public func setSession(_ sessionID: String?) {
        var detached: RUMOperationOwnership?
        _state.mutate { state in
            guard !state.isRetired, state.sessionID != sessionID else { return }
            detached = state.ownership
            state.ownership = nil
            state.sessionID = sessionID
            state.sessionStart = nil
            state.lastInteraction = nil
        }
        detached?.retire()
    }

    /// Updated on the original RUM processing queue after expiry/admission.
    public func updateSession(_ sessionID: String, start: Date, lastInteraction: Date) {
        _state.mutate {
            guard !$0.isRetired, $0.sessionID == sessionID else { return }
            $0.sessionStart = start
            $0.lastInteraction = lastInteraction
        }
    }

    public func ownership(for sessionID: String) -> RUMOperationOwnership? {
        guard isCurrent else { return nil }
        var result: RUMOperationOwnership?
        _state.mutate {
            guard !$0.isRetired, $0.sessionID == sessionID else { return }
            if let existing = $0.ownership {
                result = existing
            } else {
                let ownership = RUMOperationOwnership(origin: self, sessionID: sessionID)
                $0.ownership = ownership
                result = ownership
            }
        }
        return result
    }

    public func isSessionActive(_ sessionID: String) -> Bool {
        guard isCurrent else { return false }
        let snapshot = state
        guard !snapshot.isRetired, snapshot.sessionID == sessionID,
              let start = snapshot.sessionStart, let last = snapshot.lastInteraction,
              let feature = snapshot.feature else { return false }
        return feature.isOperationSessionActive(start: start, lastInteraction: last)
    }

    public func retire() {
        var detached: RUMOperationOwnership?
        _state.mutate {
            guard !$0.isRetired else { return }
            $0.isRetired = true
            detached = $0.ownership
            $0.ownership = nil
            $0.sessionID = nil
            $0.sessionStart = nil
            $0.lastInteraction = nil
        }
        detached?.retire()
    }

    deinit { retire() }
}

/// Original Session admission and cancellation; retains no Core, Feature or Monitor.
@_spi(Internal)
public final class RUMOperationOwnership: @unchecked Sendable {
    private struct WeakSubscriber {
        weak var value: (any RUMOperationCancellationReceiving)?
    }
    private struct State {
        var isRetired = false
        var subscribers: [ObjectIdentifier: WeakSubscriber] = [:]
    }

    public let origin: RUMOperationOrigin
    public let sessionID: String
    @ReadWriteLock private var state = State()

    fileprivate init(origin: RUMOperationOrigin, sessionID: String) {
        self.origin = origin
        self.sessionID = sessionID
    }

    public var isValid: Bool { !state.isRetired && origin.isSessionActive(sessionID) }

    /// A retired ownership refuses subscription; callbacks run after unlock.
    public func subscribe(_ subscriber: any RUMOperationCancellationReceiving) -> Bool {
        var accepted = false
        _state.mutate {
            guard !$0.isRetired else { return }
            $0.subscribers[ObjectIdentifier(subscriber)] = WeakSubscriber(value: subscriber)
            accepted = true
        }
        if !accepted { subscriber.operationOwnershipDidRetire(self) }
        return accepted
    }

    public func unsubscribe(_ subscriber: any RUMOperationCancellationReceiving) {
        _state.mutate { $0.subscribers.removeValue(forKey: ObjectIdentifier(subscriber)) }
    }

    public func retire() {
        var detached: [WeakSubscriber] = []
        _state.mutate {
            guard !$0.isRetired else { return }
            $0.isRetired = true
            detached = Array($0.subscribers.values)
            $0.subscribers.removeAll()
        }
        detached.forEach { $0.value?.operationOwnershipDidRetire(self) }
    }
}

@_spi(Internal)
public struct OwnedOperationMessage {
    public let ownership: RUMOperationOwnership
    public let attributes: [AttributeKey: AttributeValue]
    public let operation: Vital

    public init(ownership: RUMOperationOwnership, attributes: [AttributeKey: AttributeValue], operation: Vital) {
        self.ownership = ownership
        self.attributes = attributes
        self.operation = operation
    }
}


/// Separate On-only capability. Core invokes it on its serial message-bus queue.
@_spi(Internal)
public protocol RUMOperationBusModeReceiving {
    func receiveRUMOperationBusMode(owner: RUMContextHandoff.Owner, active: Bool)
}

@_spi(Internal)
extension CombinedFeatureMessageReceiver: RUMOperationBusModeReceiving {
    @_spi(Internal)
    public func receiveRUMOperationBusMode(owner: RUMContextHandoff.Owner, active: Bool) {
        for receiver in receivers {
            (receiver as? RUMOperationBusModeReceiving)?.receiveRUMOperationBusMode(owner: owner, active: active)
        }
    }
}
