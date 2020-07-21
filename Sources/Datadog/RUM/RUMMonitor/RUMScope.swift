/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol RUMScope: class {
    /// The context of this scope. Should inherit data from parent scope's context.
    var context: RUMContext { get }

    /// Processes given command. Returns:
    /// * `true` if the scope should be kept open.
    /// * `false` if the scope should be closed.
    func process(command: RUMCommand) -> Bool
}

extension RUMScope {
    /// Propagates given `command` to the child scope and manages its lifecycle by
    /// removing it if it gets closed.
    func propagate(command: RUMCommand, to chilScope: inout RUMScope?) {
        if chilScope?.process(command: command) == true {
            chilScope = nil
        }
    }

    /// Propagates given `command` through array of child scopes and manages their lifecycle by
    /// removing child scopes that get closed.
    func propagate(command: RUMCommand, to chilScopes: inout [RUMScope]) {
        chilScopes = chilScopes.filter { chilScope in
            let shouldBeClosed = chilScope.process(command: command)
            return shouldBeClosed == false
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
