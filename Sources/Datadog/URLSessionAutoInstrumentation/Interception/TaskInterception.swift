/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class TaskInterception {
    /// An identifier uniquely identifying the task interception across all `URLSessions`.
    internal let identifier: UUID
    /// The initial request send during this interception. It is, the request send from `URLSession`, not the one
    /// given by the user (as the request could have been modified in `URLSessionSwizzler`).
    internal let request: URLRequest
    /// Tells if the `request` is send to a 1st party host.
    internal let isFirstPartyRequest: Bool
    /// Task metrics collected during this interception.
    private(set) var metrics: ResourceMetrics?
    /// Task data received during this interception. Can be `nil` if task completed with error.
    private(set) var data: Data?
    /// Task completion collected during this interception.
    private(set) var completion: ResourceCompletion?
    /// Trace information propagated with the task. Not available when Tracing is disabled
    /// or when the task was created through `URLSession.dataTask(with:url)` on some iOS13+.
    private(set) var spanContext: DDSpanContext?

    init(
        request: URLRequest,
        isFirstParty: Bool
    ) {
        self.identifier = UUID()
        self.request = request
        self.isFirstPartyRequest = isFirstParty
    }

    func register(metrics: ResourceMetrics) {
        self.metrics = metrics
    }

    func register(nextData: Data) {
        if data != nil {
            self.data?.append(nextData)
        } else {
            self.data = nextData
        }
    }

    func register(completion: ResourceCompletion) {
        self.completion = completion
    }

    func register(spanContext: DDSpanContext) {
        self.spanContext = spanContext
    }

    /// Tells if the interception is done (mean: both metrics and completion were collected).
    var isDone: Bool {
        metrics != nil && completion != nil
    }
}
