/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An interface for forwarding `URLSessionDelegate` calls to `DDURLSessionDelegate`.
/// The implementation must ensure that required methods are called on the `ddURLSessionDelegate`.
@objc
public protocol __URLSessionDelegateProviding: URLSessionDelegate {
    /// Datadog delegate object.
    /// The class implementing `DDURLSessionDelegateProviding` must ensure that following method calls are forwarded to `ddURLSessionDelegate`:
    /// - `func urlSession(_:task:didFinishCollecting:)`
    /// - `func urlSession(_:task:didCompleteWithError:)`
    /// - `func urlSession(_:dataTask:didReceive:)`
    var ddURLSessionDelegate: DDURLSessionDelegate { get }
}

/// The `URLSession` delegate object which enables network requests instrumentation. **It must be
/// used together with** `Datadog.Configuration.trackURLSession(firstPartyHosts:)`.
///
/// All requests made with the `URLSession` instrumented with this delegate will be intercepted by the SDK.
@objc
open class DDURLSessionDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, __URLSessionDelegateProviding {
    public var ddURLSessionDelegate: DDURLSessionDelegate {
        return self
    }

    var instrumentation: URLSessionAutoInstrumentation? {
        core().v1.feature(URLSessionAutoInstrumentation.self)
    }

    let firstPartyURLsFilter: FirstPartyURLsFilter

    private let core: () -> DatadogCoreProtocol

    @objc
    override public init() {
        core = { defaultDatadogCore }
        firstPartyURLsFilter = FirstPartyURLsFilter(hosts: [])
        super.init()
    }

    public convenience init(in core: DatadogCoreProtocol) {
        self.init(in: core, additionalFirstPartyHosts: [])
    }

    /// Automatically tracked hosts can be customized per instance with this initializer.
    ///
    /// **NOTE:** If `trackURLSession(firstPartyHosts:)` is never called, automatic tracking will **not** take place.
    ///
    /// - Parameter additionalFirstPartyHosts: these hosts are tracked **in addition to** what was
    ///             passed to `DatadogConfiguration.Builder` via `trackURLSession(firstPartyHosts:)`
    @objc
    public convenience init(additionalFirstPartyHosts: Set<String>) {
        self.init(in: defaultDatadogCore, additionalFirstPartyHosts: additionalFirstPartyHosts)
    }

    /// Automatically tracked hosts can be customized per instance with this initializer.
    ///
    /// - Parameters:
    ///   - core: Datadog SDK core.
    ///   - additionalFirstPartyHosts: additionalFirstPartyHosts: these hosts are tracked **in addition to** what was
    ///                                passed to `DatadogConfiguration.Builder` via `trackURLSession(firstPartyHosts:)`
    public init(in core: @autoclosure @escaping () -> DatadogCoreProtocol, additionalFirstPartyHosts: Set<String>) {
        self.core = core
        self.firstPartyURLsFilter = FirstPartyURLsFilter(hosts: additionalFirstPartyHosts)
        super.init()
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        instrumentation?.interceptor.taskMetricsCollected(task: task, metrics: metrics)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // NOTE: This delegate method is only called for `URLSessionTasks` created without the completion handler.
        instrumentation?.interceptor.taskCompleted(task: task, error: error)
    }

    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // NOTE: This delegate method is only called for `URLSessionTasks` created without the completion handler.
        instrumentation?.interceptor.taskReceivedData(task: dataTask, data: data)
    }
}
