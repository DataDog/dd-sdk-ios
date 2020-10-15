/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

@objc
open class DDURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    var interceptor: URLSessionInterceptorType?

    @objc
    override public init() {
        interceptor = URLSessionAutoInstrumentation.instance?.interceptor
        if interceptor == nil {
            let error = ProgrammerError(
                description: """
                To use `DDURLSessionDelegate` you must specify first party hosts in `Datadog.Configuration` -
                use `track(firstPartyHosts:)` to define which requests should be tracked.
                """
            )
            consolePrint("\(error)")
        }
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        interceptor?
            .taskMetricsCollected(urlSession: session, task: task, metrics: metrics)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // NOTE: This delegate method is only called for `URLSessionTasks` created without the completion handler.

        interceptor?
            .taskCompleted(urlSession: session, task: task, error: error)
    }
}
