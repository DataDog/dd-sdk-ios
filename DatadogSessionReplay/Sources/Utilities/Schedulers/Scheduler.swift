/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// Schedules operations for later execution.
internal protocol Scheduler {
    /// The queue that operations are executed on.
    var queue: Queue { get }

    /// Adds operation to the scheduler.
    /// Operations can be added no matter if the scheduler is running.
    func schedule(operation: @escaping () -> Void)

    /// Starts executing scheduled operations.
    func start()

    /// Stops executing scheduled operations.
    func stop()
}
#endif
