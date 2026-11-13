/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Retains the first event independently of registrations. Only the reserving installer may publish it.
internal final class FirstFlagsCallbacks {
    private struct State {
        var event: FlagsClientEvent?
        var isPublished = false
        var isInvalidated = false
        var pending: [Registration] = []
    }

    @ReadWriteLock
    private var state = State()

    deinit {
        invalidate()
    }

    /// Repository teardown must cancel unclaimed registrations even while publication retains this helper.
    func invalidate() {
        var registrations: [Registration] = []
        _state.mutate { state in
            state.isInvalidated = true
            registrations = state.pending
            state.pending = []
        }
        registrations.forEach { $0.cancel() }
    }

    func reserve(keys: [String]) -> (() -> Void)? {
        var reserved = false
        _state.mutate { state in
            guard !state.isInvalidated, state.event == nil else {
                return
            }
            state.event = FlagsClientEvent(type: .configurationChanged, flagsChanged: keys)
            reserved = true
        }
        guard reserved else {
            return nil
        }
        return { [weak self] in self?.publish() }
    }

    func register(_ callback: @escaping FlagsClientEventListener) -> any FlagsSubscription {
        let registration = Registration(callback: callback, owner: self)
        var replay: FlagsClientEvent?
        var invalidated = false
        _state.mutate { state in
            guard !state.isInvalidated else {
                invalidated = true
                return
            }
            replay = state.isPublished ? state.event : nil
            state.pending.append(registration)
        }
        if invalidated { registration.cancel() }
        if let replay { registration.deliver(replay) }
        return registration
    }

    private func publish() {
        var event: FlagsClientEvent?
        var registrations: [Registration] = []
        _state.mutate { state in
            guard !state.isInvalidated, !state.isPublished, let reserved = state.event else {
                return
            }
            state.isPublished = true
            event = reserved
            // Keep unclaimed registrations reachable by repository teardown during the broadcast.
            registrations = state.pending
        }
        guard let event else {
            return
        }
        registrations.forEach { $0.deliver(event) }
    }

    private func claim(_ registration: Registration) -> FlagsClientEventListener? {
        var claimed: FlagsClientEventListener?
        _state.mutate { state in
            guard !state.isInvalidated else {
                return
            }
            // Claiming and invalidation share one boundary, including during capture destruction.
            claimed = registration.takeCallback()
            state.pending.removeAll { $0 === registration }
        }
        return claimed
    }

    private func remove(_ registration: Registration) {
        _state.mutate { $0.pending.removeAll { $0 === registration } }
    }

    // The callback is synchronized. The weak owner is assigned only during initialization;
    // its removal operation uses the owner lock. No application callbacks run under either lock.
    private final class Registration: FlagsSubscription, @unchecked Sendable {
        @ReadWriteLock
        private var callback: FlagsClientEventListener?
        private weak var owner: FirstFlagsCallbacks?

        init(callback: @escaping FlagsClientEventListener, owner: FirstFlagsCallbacks) {
            self.callback = callback
            self.owner = owner
        }

        func cancel() {
            let released = takeCallback()
            owner?.remove(self)
            // Captured objects may run application code in deinit; release them outside both locks.
            withExtendedLifetime(released) {}
        }

        func takeCallback() -> FlagsClientEventListener? {
            var taken: FlagsClientEventListener?
            _callback.mutate { callback in
                taken = callback
                callback = nil
            }
            return taken
        }

        func deliver(_ event: FlagsClientEvent) {
            let claimed = owner?.claim(self)
            claimed?(event)
        }
    }
}
