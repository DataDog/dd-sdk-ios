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
        var pending: [Registration] = []
    }

    @ReadWriteLock
    private var state = State()

    deinit {
        var registrations: [Registration] = []
        _state.mutate { state in
            registrations = state.pending
            state.pending = []
        }
        registrations.forEach { $0.cancel() }
    }

    func reserve(keys: [String]) -> (() -> Void)? {
        var reserved = false
        _state.mutate { state in
            guard state.event == nil else {
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
        _state.mutate { state in
            replay = state.isPublished ? state.event : nil
            if replay == nil { state.pending.append(registration) }
        }
        if let replay { registration.deliver(replay) }
        return registration
    }

    private func publish() {
        var event: FlagsClientEvent?
        var registrations: [Registration] = []
        _state.mutate { state in
            guard !state.isPublished, let reserved = state.event else {
                return
            }
            state.isPublished = true
            event = reserved
            registrations = state.pending
            state.pending = []
        }
        guard let event else {
            return
        }
        registrations.forEach { $0.deliver(event) }
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
            var released: FlagsClientEventListener?
            _callback.mutate { callback in
                released = callback
                callback = nil
            }
            owner?.remove(self)
            // Captured objects may run application code in deinit; release them outside both locks.
            withExtendedLifetime(released) {}
        }

        func deliver(_ event: FlagsClientEvent) {
            var claimed: FlagsClientEventListener?
            _callback.mutate { callback in
                // Taking the callback is the delivery-start boundary shared with cancellation.
                claimed = callback
                callback = nil
            }
            claimed?(event)
        }
    }
}
