/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol RUMScope: AnyObject {
    /// Processes given command. Returns:
    /// * `true` if the scope should be kept open.
    /// * `false` if the scope should be closed.
    func process(command: RUMCommand, context: DatadogV1Context, writer: Writer) -> Bool
}

extension RUMScope {
    /// Propagates given `command` to the child scope and manages its lifecycle by
    /// removing it if it gets closed.
    ///
    /// Returns the `childScope` requested to be kept open, `nil` if it requests to close.
    static func scope<S: RUMScope>(byPropagating command: RUMCommand, in scope: S?, context: DatadogV1Context, writer: Writer) -> S? {
        guard
            let scope = scope,
            scope.process(command: command, context: context, writer: writer)
        else {
            return nil
        }

        return scope
    }
}

extension Array where Element: RUMScope {
    /// Propagates given `command` through array of child scopes and manages their lifecycle by
    /// removing child scopes that get closed.
    ///
    /// Returns the `childScopes` array by removing scopes which requested to be closed.
    static func scopes(byPropagating command: RUMCommand, in scopes: [Element], context: DatadogV1Context, writer: Writer) -> [Element] {
        return scopes.filter { scope in
            scope.process(command: command, context: context, writer: writer)
        }
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
