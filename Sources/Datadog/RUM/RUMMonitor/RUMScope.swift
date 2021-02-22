/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal enum RUMScopeState {
    case open
    case closing
    case closed
    case discarded
}

internal protocol RUMScope: class {
    /// Tracks a given `RUMScope` state.
    /// The state is updated based on the return value of `RUMScope.process`.
    var state: RUMScopeState { set get }

    /// Processes given command.
    /// Returns a `RUMScopeState`
    /// * `open` if the scope should be kept open.
    /// * `closing` if the scope should be kept open a little longer.
    /// * `closed` if the scope should be closed.
    /// * `discarded` if the scope should be closed and any related state should be rolled back.
    func process(command: RUMCommand) -> RUMScopeState
}

extension RUMScope {
    /// Propagates given `command` to the child scope and manages its lifecycle by
    /// removing it if it gets closed.
    ///
    /// Returns the `childScope` requested to be kept open, `nil` if it requests to close.
    func manage<S: RUMScope>(childScope: S?, byPropagatingCommand command: RUMCommand) -> (state: RUMScopeState, scope: S?) {
        let state = childScope?.process(command: command) ?? .closed
        childScope?.state = state
        if state == .closed || state == .discarded {
            return (state, nil)
        } else {
            return (state, childScope)
        }
    }
}

extension Array where Element: RUMScope {
    /// Propagates given `command` through array of scopes and manages their lifecycle by
    /// removing scopes that get closed or discarded.
    /// Also provides a callback with scopes to be removed to help keep external state consistent.
    mutating func manage(byPropagatingCommand command: RUMCommand, callback: ((Element) -> Void)? = nil) {
        removeAll { scope in
            let managedScope = scope.manage(childScope: scope, byPropagatingCommand: command).scope
            let shouldBeRemove = managedScope == nil
            if shouldBeRemove {
                callback?(scope)
            }
            return shouldBeRemove
        }
    }
}

extension Dictionary where Value: RUMScope {
    /// Propagates given `command` through a dictionary of scopes and manages their lifecycle by
    /// removing scopes that get closed or discarded.
    /// Also provides a callback with scopes to be removed to help keep external state consistent.
    mutating func manage(byPropagatingCommand command: RUMCommand, callback: ((Value) -> Void)? = nil) {
        filter { _, scope in
            let managedScope = scope.manage(childScope: scope, byPropagatingCommand: command).scope
            let shouldBeRemove = managedScope == nil
            if shouldBeRemove {
                callback?(scope)
            }
            return shouldBeRemove
        }
        .forEach { removeValue(forKey: $0.key) }
    }
}

extension Dictionary where Key == AttributeKey, Value == AttributeValue {
    /// Merges given `rumCommandAttributes` to current dictionary, by overwriting values.
    mutating func merge(rumCommandAttributes: [AttributeKey: AttributeValue]?) {
        guard let additionalAttributes = rumCommandAttributes else {
            return
        }
        merge(additionalAttributes) { _, new in new }
    }
}
