/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol RUMScope: AnyObject {
    /// Container bundling dependencies for this scope.
    var dependencies: RUMScopeDependencies { get }

    /// Processes given command. Returns:
    /// * `true` if the scope should be kept open.
    /// * `false` if the scope should be closed.
    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool
}

extension RUMScope {
    /// Propagates given `command` and manages its lifecycle by returning `nil` if it gets closed.
    ///
    /// Returns `self`  to be kept open, `nil` if it requests to close.
    func scope(byPropagating command: RUMCommand, context: DatadogContext, writer: Writer) -> Self? {
        process(command: command, context: context, writer: writer) ? self : nil
    }
}

extension Array where Element: RUMScope {
    /// Propagates given `command` through this array of scopes and manages their lifecycle by
    /// filtering scopes that get closed.
    ///
    /// Returns the `childScopes` array by removing scopes which requested to be closed.
    func scopes(byPropagating command: RUMCommand, context: DatadogContext, writer: Writer) -> [Element] {
        return filter { scope in
            scope.process(command: command, context: context, writer: writer)
        }
    }
}
