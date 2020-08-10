/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol RUMScope: class {
    /// Processes given command. Returns:
    /// * `true` if the scope should be kept open.
    /// * `false` if the scope should be closed.
    func process(command: RUMCommand) -> Bool
}

extension RUMScope {
    /// Propagates given `command` to the child scope and manages its lifecycle by
    /// removing it if it gets closed.
    ///
    /// Returns the `childScope` requested to be kept open, `nil` if it requests to close.
    func manage<S: RUMScope>(childScope: S?, byPropagatingCommand command: RUMCommand) -> S? {
        if childScope?.process(command: command) == false {
            return nil
        } else {
            return childScope
        }
    }

    /// Propagates given `command` through array of child scopes and manages their lifecycle by
    /// removing child scopes that get closed.
    ///
    /// Returns the `childScopes` array by removing scopes which requested to be closed.
    func manage<S: RUMScope>(childScopes: [S], byPropagatingCommand command: RUMCommand) -> [S] {
        return childScopes.filter { childScope in
            let shouldBeKept = childScope.process(command: command)
            return shouldBeKept
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
