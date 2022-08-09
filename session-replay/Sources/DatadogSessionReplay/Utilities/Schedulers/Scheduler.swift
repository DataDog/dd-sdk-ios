/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Schedules operations and fires them in a recurring way.
internal protocol Scheduler {
    /// Adds operation to the scheduler.
    /// Operations can be added no matter if this scheduler is running or not.
    func schedule(operation: @escaping () -> Void)

    /// Starts repeating scheduled operations.
    func start()

    /// Stops repeating scheduled operations.
    func stop()
}
