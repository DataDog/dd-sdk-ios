/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The `URLSession` delegate object which enables network requests instrumentation. **It must be
/// used together with** `Datadog.Configuration.trackURLSession(firstPartyHosts:)`.
///
/// All requests made with the `URLSession` instrumented with this delegate will be intercepted by the SDK.
@objc
open class DDURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    var interceptor: URLSessionInterceptorType?
    let firstPartyURLsFilter: FirstPartyURLsFilter?

    @objc
    override public init() {
        Self.datadogInitializationCheck()
        firstPartyURLsFilter = nil
        interceptor = URLSessionAutoInstrumentation.instance?.interceptor
    }

    /// Automatically tracked hosts can be customized per instance with this initializer
    /// - Parameter additionalFirstPartyHosts: these hosts are tracked **in addition to** what was
    /// passed to `DatadogConfiguration.Builder` via `trackURLSession(firstPartyHosts:)`
    /// **NOTE:** If `trackURLSession(firstPartyHosts:)` is never called, automatic tracking will **not** take place
    @objc
    public init(additionalFirstPartyHosts: Set<String>) {
        // NOTE: RUMM-954 copy&pasting `init()` is a conscious decision.
        // otherwise `DDURLSessionDelegateAsSuperclassTests` fails.
        // if `init()` was made convenience and call the designated `init` below,
        // that would result in potential breaking changes.
        // host projects would need to change their `init()`s in subclasses.
        // we can fix this in v2.0
        Self.datadogInitializationCheck()
        firstPartyURLsFilter = FirstPartyURLsFilter(hosts: additionalFirstPartyHosts)
        interceptor = URLSessionAutoInstrumentation.instance?.interceptor
    }

    private static func datadogInitializationCheck() {
        if URLSessionAutoInstrumentation.instance?.interceptor == nil {
            let error = ProgrammerError(
                description: """
                `Datadog.initialize()` must be called before initializing the `DDURLSessionDelegate` and
                first party hosts must be specified in `Datadog.Configuration`: `trackURLSession(firstPartyHosts:)`
                to enable network requests tracking.
                """
            )
            consolePrint("\(error)")
        }
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        interceptor?.taskMetricsCollected(task: task, metrics: metrics)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // NOTE: This delegate method is only called for `URLSessionTasks` created without the completion handler.

        interceptor?.taskCompleted(task: task, error: error)
    }
}
