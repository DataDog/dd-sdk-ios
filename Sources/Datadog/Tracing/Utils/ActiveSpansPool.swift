/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import os.activity

/// This symbol is only accesible in Activity framework from Objective-C because uses a macro to create it, to use it from Swift
/// we must recreate whats done in the macro in Swift code.
internal let OS_ACTIVITY_CURRENT = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_os_activity_current"), to: os_activity_t.self)

/// Used to reference the active span in the current execution context.
internal class ActivityReference {
    let activityId: os_activity_id_t
    fileprivate var activityState = os_activity_scope_state_s()

    init() {
        let dso = UnsafeMutableRawPointer(mutating: #dsohandle)
        let activity = _os_activity_create(dso, "DDSpanActivityReference", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT)
        activityId = os_activity_get_identifier(activity, nil)
        os_activity_scope_enter(activity, &activityState)
    }

    deinit {
        os_activity_scope_leave(&activityState)
    }
}

/// Helper class to get the current Span
internal class ActiveSpansPool {
    private var contextMap = [os_activity_id_t: DDSpan]()
    private let rlock = NSRecursiveLock()

    /// Returns the Span from the current context
    func getActiveSpan() -> DDSpan? {
        // We should try to traverse all hierarchy to locate the Span, but I could not find a way, just direct parent
        var parentIdent: os_activity_id_t = 0
        let activityIdent = os_activity_get_identifier(OS_ACTIVITY_CURRENT, &parentIdent)
        var returnSpan: DDSpan?
        rlock.lock()
        returnSpan = contextMap[activityIdent] ?? contextMap[parentIdent]
        rlock.unlock()
        return returnSpan
    }

    func addSpan(span: DDSpan, activityReference: ActivityReference) {
        rlock.lock()
        contextMap[activityReference.activityId] = span
        rlock.unlock()
    }

    func removeSpan(activityReference: ActivityReference) {
        rlock.lock()
        contextMap[activityReference.activityId] = nil
        rlock.unlock()
    }

#if DD_SDK_COMPILED_FOR_TESTING
    /// This explicit way of destroying `ActiveSpansPool` was added after noticing RUMM-2904. It is there to keep test coverage
    /// for a scenario of incorret use of `span.setActive()` API. Until RUMM-2904 is fixed, `destroy()` is necessary to not
    /// leak the `core` object memory in tests. It should be removed after fixing the problem.
    ///
    /// TODO: RUMM-2904 Calling `span.setActive()` multiple times introduces retain cycle and leaks `DatadogCore` object
    func destroy() {
        rlock.lock()
        contextMap = [:]
        rlock.unlock()
    }
#endif
}
