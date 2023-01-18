/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An observer subscribing to a `ValuePublisher`.
internal protocol ValueObserver: AnyObject {
    associatedtype ObservedValue

    /// Notifies this observer on the value change. Called on the publisher's queue.
    /// If the `ObservedValue` conforms to `Equatable`, only distinct changes will be notified.
    ///
    /// **Note:** as this method is executed on the publisher's queue, call to `publisher.publishSync(_:)`
    /// from its implementation will result in deadlock. If the observed value must be updated, use `publishAsync(_:)` instead.
    func onValueChanged(oldValue: ObservedValue, newValue: ObservedValue)
}

/// Manages the `Value` in a thread safe manner and notifies subscribed `ValueObservers` on its change.
internal final class ValuePublisher<Value> {
    /// Type erasure for `ValueObserver` type.
    private struct AnyObserver<ObservedValue> {
        let notifyValueChanged: (ObservedValue, ObservedValue) -> Void
        let object: AnyObject

        init<Observer: ValueObserver>(wrapped: Observer) where Observer.ObservedValue == ObservedValue {
            self.object = wrapped
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
    private var unsafeValue: Value {
        didSet {
            unsafeObservers.forEach { observer in
                observer.notifyValueChanged(oldValue, unsafeValue)
            }
        }
    }

    required init(initialValue: Value) {
        self.unsafeValue = initialValue
        self.unsafeObservers = []
    }

    /// Returns the last published value or initial value if none was published yet.
    var currentValue: Value {
        concurrentQueue.sync { unsafeValue }
    }

    /// Updates the `currentValue` synchronously, with blocking the caller thread.
    func publishSync(_ newValue: Value) {
        concurrentQueue.sync(flags: .barrier) { unsafeValue = newValue }
    }

    /// Updates the `currentValue` asynchronously, without blocking the caller thread.
    func publishAsync(_ newValue: Value) {
        concurrentQueue.async(flags: .barrier) { self.unsafeValue = newValue }
    }

    /// Updates the `currentValue` asynchronously, without blocking the caller thread.
    func mutateAsync(block: @escaping (inout Value) -> Void) {
        concurrentQueue.async(flags: .barrier) { block(&self.unsafeValue) }
    }

    /// Registers an observer that will be notified on all value changes.
    /// All calls to the `observer` will be synchronised using internal concurrent queue.
    func subscribe<Observer: ValueObserver>(_ observer: Observer) where Observer.ObservedValue == Value {
        concurrentQueue.async(flags: .barrier) {
            self.unsafeObservers.append(AnyObserver(wrapped: observer))
        }
    }

    /// Registers an observer that will be notified on dictinct value changes.
    /// All calls to the `observer` will be synchronised using internal concurrent queue.
    func subscribe<Observer: ValueObserver>(_ observer: Observer) where Observer.ObservedValue == Value, Value: Equatable {
        concurrentQueue.async(flags: .barrier) {
            let distinctObserver = DistinctValueObserver(wrapped: observer)
            self.unsafeObservers.append(AnyObserver(wrapped: distinctObserver))
        }
    }

    /// Removes an observer so that it will not be notified on all value changes anymore.
    func unsubscribe<Observer: ValueObserver>(_ observer: Observer) where Observer.ObservedValue == Value {
        concurrentQueue.async(flags: .barrier) {
            self.unsafeObservers.removeAll { existingObserver in
                return existingObserver.object === observer
            }
        }
    }
}

// MARK: - Helpers

/// `ValueObserver` wrapper which notifies the wrapped observer only on distinct changes of the `Equatable` value.
private class DistinctValueObserver<EquatableValue: Equatable>: ValueObserver {
    private let wrappedOnValueChanged: (EquatableValue, EquatableValue) -> Void

    init<WrappedObserver: ValueObserver>(wrapped: WrappedObserver) where WrappedObserver.ObservedValue == EquatableValue {
        self.wrappedOnValueChanged = wrapped.onValueChanged
    }

    func onValueChanged(oldValue: EquatableValue, newValue: EquatableValue) {
        if newValue != oldValue {
            wrappedOnValueChanged(oldValue, newValue)
        }
    }
}
