/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Manages the `Value` in a thread safe manner and notifies subscribed `ValueObservers` on its change.
internal class ValuePublisher<Value> {
    /// Type erasure for `ValueObserver` types.
    private struct AnyObserver<ObservedValue> {
        let notifyValueChanged: (ObservedValue, ObservedValue) -> Void

        init<Observer: ValueObserver>(wrapped: Observer) where Observer.ObservedValue == ObservedValue {
            self.notifyValueChanged = wrapped.onValueChanged
        }
    }

    /// The queue used to synchronize the access to the `unsafeValue`.
    /// Concurrent queue is used for performant reads, `.barrier` must be used to make writes exclusive.
    private let concurrentQueue = DispatchQueue(
        label: "com.datadoghq.value-publisher-\(type(of: Value.self))",
        attributes: .concurrent
    )
    /// The array of value observers - must be accessed from the `queue`.
    private var unsafeObservers: [AnyObserver<Value>]
    /// The managed `Value` - must be accessed from the `queue`.
    private var unsafeValue: Value

    /// The model used for synchronizing `currentValue` updates.
    enum UpdatesModel {
        /// The `currentValue` will be updated synchronously, blocking the caller thread.
        case synchronous
        /// The `currentValue` will be updated asynchronously, without blocking the caller thread.
        case asynchronous
    }

    /// The synchronization model for updating the `unsafeValue`.
    private let updatesModel: UpdatesModel

    init(initialValue: Value, updatesModel: UpdatesModel) {
        self.unsafeValue = initialValue
        self.unsafeObservers = []
        self.updatesModel = updatesModel
    }

    /// Registers an observer that will be notified on the value changes.
    /// All calls to the `observer` will be synchronised using internal concurrent queue.
    func subscribe<Observer: ValueObserver>(_ observer: Observer) where Observer.ObservedValue == Value {
        concurrentQueue.async(flags: .barrier) {
            self.unsafeObservers.append(AnyObserver(wrapped: observer))
        }
    }

    var currentValue: Value {
        get {
            concurrentQueue.sync { unsafeValue }
        }
        set {
            switch updatesModel {
            case .synchronous:
                concurrentQueue.sync(flags: .barrier) { updateAndNotifyObservers(newValue: newValue) }
            case .asynchronous:
                concurrentQueue.async(flags: .barrier) { self.updateAndNotifyObservers(newValue: newValue) }
            }
        }
    }

    private func updateAndNotifyObservers(newValue: Value) {
        let oldValue = self.unsafeValue
        self.unsafeValue = newValue
        self.unsafeObservers.forEach { observer in
            observer.notifyValueChanged(oldValue, newValue)
        }
    }
}

/// An observer subscribing to a `ValuePublisher`.
internal protocol ValueObserver {
    associatedtype ObservedValue

    /// Notifies this observer on the value change. Called on the publisher's queue.
    func onValueChanged(oldValue: ObservedValue, newValue: ObservedValue)
}
