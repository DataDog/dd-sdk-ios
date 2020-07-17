/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import os.activity

/// Helper class to get the current Span
internal struct ActiveSpanUtils {
    static let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    static let sym = dlsym(RTLD_DEFAULT, "_os_activity_current")
    static let OS_ACTIVITY_CURRENT = unsafeBitCast(sym, to: os_activity_t.self)

    static var contextMap = [os_activity_id_t: DDSpan]()
    static let rlock = NSRecursiveLock()

    /// Returns the Span from the current context
    internal static func getActiveSpan() -> DDSpan? {
        // We should try to traverse all hierarchy to locate the Span, but I could not find a way, just direct parent
        var parentIdent: os_activity_id_t = 0
        let activityIdent = os_activity_get_identifier(OS_ACTIVITY_CURRENT, &parentIdent)
        var returnSpan: DDSpan?
        rlock.lock()
returnSpan = contextMap[activityIdent] ?? contextMap[parentIdent]
        rlock.unlock()
        return returnSpan
    }

    static func addSpan(_ span: DDSpan) {
        rlock.lock()
        contextMap[span.ddContext.activityId] = span
        rlock.unlock()
    }

    static func removeSpan(_ span: DDSpan) {
        rlock.lock()
        contextMap[span.ddContext.activityId] = nil
        rlock.unlock()
    }
}
