/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The `URLSession` delegate object which enables network requests instrumentation. **It must be
/// used together with** `Datadog.Configuration.trackURLSession(firstPartyHosts:)`.
///
/// All requests made with the `URLSession` instrumented with this delegate will be intercepted by the SDK.
@objc
open class DDURLSessionDelegate: DatadogURLSessionDelegate {
    var instrumentation: URLSessionAutoInstrumentation? {
        let core = self.core ?? defaultDatadogCore
        return core.v1.feature(URLSessionAutoInstrumentation.self)
    }

    override open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        instrumentation?.interceptor.taskMetricsCollected(task: task, metrics: metrics)
        super.urlSession(session, task: task, didFinishCollecting: metrics)
    }

    override open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // NOTE: This delegate method is only called for `URLSessionTasks` created without the completion handler.
        instrumentation?.interceptor.taskCompleted(task: task, error: error)
        super.urlSession(session, task: task, didCompleteWithError: error)
    }

    override open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // NOTE: This delegate method is only called for `URLSessionTasks` created without the completion handler.
        instrumentation?.interceptor.taskReceivedData(task: dataTask, data: data)
        super.urlSession(session, dataTask: dataTask, didReceive: data)
    }
}
