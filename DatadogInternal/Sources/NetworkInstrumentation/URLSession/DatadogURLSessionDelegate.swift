/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@available(*, deprecated, message: "Use `URLSessionInstrumentation.enable(with:)` instead.")
public typealias DDURLSessionDelegate = DatadogURLSessionDelegate

/// An interface for forwarding `URLSessionDelegate` calls to `DDURLSessionDelegate`.
/// The implementation must ensure that required methods are called on the `ddURLSessionDelegate`.
@objc
@available(*, deprecated, message: "Use `URLSessionInstrumentation.enable(with:)` instead.")
public protocol __URLSessionDelegateProviding: URLSessionDelegate {
    /// Datadog delegate object.
    /// 
    /// The class implementing `DDURLSessionDelegateProviding` must ensure that following method calls are forwarded to `ddURLSessionDelegate`:
    /// - `func urlSession(_:task:didFinishCollecting:)`
    /// - `func urlSession(_:task:didCompleteWithError:)`
    /// - `func urlSession(_:dataTask:didReceive:)`
    var ddURLSessionDelegate: DatadogURLSessionDelegate { get }
}

/// The `URLSession` delegate object which enables network requests instrumentation. **It must be
/// used together with** `DatadogRUM` or `DatadogTrace`.
///
/// All requests made with the `URLSession` instrumented with this delegate will be intercepted by the SDK.
@objc
@available(*, deprecated, message: "Use `URLSessionInstrumentation.enable(with:)` instead.")
open class DatadogURLSessionDelegate: NSObject, URLSessionDataDelegate {
    var interceptor: URLSessionInterceptor? {
        let core = self.core ?? CoreRegistry.default
        return URLSessionInterceptor.shared(in: core)
    }

    let swizzler = NetworkInstrumentationSwizzler()

    /// The instance of the SDK core notified by this delegate.
    ///
    /// It must be a weak reference, because `URLSessionDelegate` can last longer than core instance.
    /// Any `URLSession` will retain its delegate until `.invalidateAndCancel()` is called.
    private weak var core: DatadogCoreProtocol?

    @objc
    override public init() {
        core = nil
        super.init()
        try? swizzle(firstPartyHosts: .init())
    }

    /// Automatically tracked hosts can be customized per instance with this initializer.
    ///
    /// **NOTE:** If `trackURLSession(firstPartyHostsWithHeaderTypes:)` is never called, automatic tracking will **not** take place.
    ///
    /// - Parameter additionalFirstPartyHostsWithHeaderTypes: these hosts are tracked **in addition to** what was
    /// passed to `DatadogConfiguration.Builder` via `trackURLSession(firstPartyHostsWithHeaderTypes:)`
    public convenience init(additionalFirstPartyHostsWithHeaderTypes: [String: Set<TracingHeaderType>]) {
        self.init(
            in: nil,
            additionalFirstPartyHostsWithHeaderTypes: additionalFirstPartyHostsWithHeaderTypes
        )
    }

    /// Automatically tracked hosts can be customized per instance with this initializer.
    ///
    /// **NOTE:** If `trackURLSession(firstPartyHosts:)` is never called, automatic tracking will **not** take place.
    ///
    /// - Parameter additionalFirstPartyHosts: these hosts are tracked **in addition to** what was
    /// passed to `DatadogConfiguration.Builder` via `trackURLSession(firstPartyHosts:)`
    @objc
    public convenience init(additionalFirstPartyHosts: Set<String>) {
        self.init(
            in: nil,
            additionalFirstPartyHostsWithHeaderTypes: additionalFirstPartyHosts.reduce(into: [:], { partialResult, host in
                partialResult[host] = [.datadog, .tracecontext]
            })
        )
    }

    /// Automatically tracked hosts can be customized per instance with this initializer.
    ///
    /// **NOTE:** If `trackURLSession(firstPartyHostsWithHeaderTypes:)` is never called, automatic tracking will **not** take place.
    ///
    /// - Parameters:
    ///   - core: Datadog SDK instance (or `nil` to use default SDK instance).
    ///   - additionalFirstPartyHosts: these hosts are tracked **in addition to** what was
    ///                                passed to `DatadogConfiguration.Builder` via `trackURLSession(firstPartyHosts:)`
    public init(
        in core: DatadogCoreProtocol? = nil,
        additionalFirstPartyHostsWithHeaderTypes: [String: Set<TracingHeaderType>] = [:]
    ) {
        self.core = core
        super.init()
        try? swizzle(firstPartyHosts: FirstPartyHosts(additionalFirstPartyHostsWithHeaderTypes))
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        interceptor?.task(task, didFinishCollecting: metrics)
        if #available(iOS 15, tvOS 15, *) {
            // iOS 15 and above, didCompleteWithError is not called hence we use task state to detect task completion
            // while prior to iOS 15, task state doesn't change to completed hence we use didCompleteWithError to detect task completion
            interceptor?.task(task, didCompleteWithError: task.error)
        }
    }

    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // NOTE: This delegate method is only called for `URLSessionTasks` created without the completion handler.
        interceptor?.task(dataTask, didReceive: data)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // NOTE: This delegate method is only called for `URLSessionTasks` created without the completion handler.
        interceptor?.task(task, didCompleteWithError: error)
    }

    private func swizzle(firstPartyHosts: FirstPartyHosts) throws {
        try swizzler.swizzle(
            interceptResume: { [weak self] task in
                guard
                    let interceptor = self?.interceptor,
                    let provider = task.dd.delegate as? __URLSessionDelegateProviding,
                    provider.ddURLSessionDelegate == self // intercept task with self as delegate
                else {
                    return
                }

                if let currentRequest = task.currentRequest {
                    let request = interceptor.intercept(request: currentRequest, additionalFirstPartyHosts: firstPartyHosts)
                    task.dd.override(currentRequest: request)
                }

                interceptor.intercept(task: task, additionalFirstPartyHosts: firstPartyHosts)
            }
        )

        try swizzler.swizzle(
            interceptCompletionHandler: { [weak self] task, _, error in
                self?.interceptor?.task(task, didCompleteWithError: error)
            }
        )
    }

    deinit {
        swizzler.unswizzle()
    }
}

@available(*, deprecated, message: "Use `URLSessionInstrumentation.enable(with:)` instead.")
extension DatadogURLSessionDelegate: __URLSessionDelegateProviding {
    public var ddURLSessionDelegate: DatadogURLSessionDelegate { self }
}
