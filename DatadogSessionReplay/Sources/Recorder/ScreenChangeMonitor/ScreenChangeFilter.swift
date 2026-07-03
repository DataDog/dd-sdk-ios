/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

/// Controls when observed layer callbacks become screen changes.
internal final class ScreenChangeFilter {
    private var ignoredScopesCount = 0

    var acceptsChanges: Bool {
        dd_assert(Thread.isMainThread, "ScreenChangeFilter must be used from the main thread")
        return ignoredScopesCount == 0
    }

    func ignoringChanges<T>(_ operation: () throws -> T) rethrows -> T {
        dd_assert(Thread.isMainThread, "ScreenChangeFilter must be used from the main thread")

        ignoredScopesCount += 1
        defer {
            ignoredScopesCount -= 1
        }

        return try operation()
    }
}
#endif
