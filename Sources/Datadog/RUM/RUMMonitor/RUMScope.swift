/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol RUMScope: class {
    /// The context of this scope. Should inherit data from parent scope's context.
    var context: RUMContext { get }

    /// Processes given command and returns `true` when the scope should be closed.
    func process(command: RUMCommand) -> Bool
}
