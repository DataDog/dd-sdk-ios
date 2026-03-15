/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public protocol Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush()

    /// Awaits completion of all asynchronous operations without blocking a thread.
    func flush() async
}

extension Flushable {
    /// Default implementation delegates to the synchronous version.
    public func flush() async {
        let syncFlush: () -> Void = self.flush
        syncFlush()
    }
}
