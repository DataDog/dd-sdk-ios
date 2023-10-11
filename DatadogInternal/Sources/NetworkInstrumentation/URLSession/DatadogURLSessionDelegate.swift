/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@available(*, deprecated, message: "Use URLSessionInstrumentation instead.")
public typealias DDURLSessionDelegate = DatadogURLSessionDelegate

/// An interface for forwarding `URLSessionDelegate` calls to `DDURLSessionDelegate`.
/// The implementation must ensure that required methods are called on the `ddURLSessionDelegate`.
@objc
@available(*, deprecated, message: "Use URLSessionInstrumentation instead.")
public protocol __URLSessionDelegateProviding: URLSessionDelegate {
}

/// The `URLSession` delegate object which enables network requests instrumentation. **It must be
/// used together with** `DatadogRUM` or `DatadogTrace`.
///
/// All requests made with the `URLSession` instrumented with this delegate will be intercepted by the SDK.
@objc
@available(*, deprecated, message: "Use URLSessionInstrumentation instead.")
open class DatadogURLSessionDelegate: NSObject, URLSessionDataDelegate {
    var interceptor: URLSessionInterceptor? {
        let core = self.core ?? CoreRegistry.default
        return URLSessionInterceptor.shared(in: core)
    }

    /* private */ public let firstPartyHosts: FirstPartyHosts

    /// The instance of the SDK core notified by this delegate.
    ///
    /// It must be a weak reference, because `URLSessionDelegate` can last longer than core instance.
    /// Any `URLSession` will retain its delegate until `.invalidateAndCancel()` is called.
    private weak var core: DatadogCoreProtocol?

    @objc
    override public init() {
        core = nil
        firstPartyHosts = .init()

        URLSessionInstrumentation.enable(
            with: .init(
                delegateClass: DatadogURLSessionDelegate.self,
                firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: firstPartyHosts.hostsWithTracingHeaderTypes)
            ),
            in: core ?? CoreRegistry.default
        )

        super.init()
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
                partialResult[host] = [.datadog]
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
        self.firstPartyHosts = FirstPartyHosts(additionalFirstPartyHostsWithHeaderTypes)

        URLSessionInstrumentation.enable(
            with: .init(
                delegateClass: DatadogURLSessionDelegate.self,
                firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: firstPartyHosts.hostsWithTracingHeaderTypes)
            ),
            in: core ?? CoreRegistry.default
        )
        super.init()
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        interceptor?.task(task, didFinishCollecting: metrics)
    }

    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // NOTE: This delegate method is only called for `URLSessionTasks` created without the completion handler.
        interceptor?.task(dataTask, didReceive: data)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // NOTE: This delegate method is only called for `URLSessionTasks` created without the completion handler.
        interceptor?.task(task, didCompleteWithError: error)
    }
}

@available(*, deprecated, message: "Use URLSessionInstrumentation instead.")
extension DatadogURLSessionDelegate: __URLSessionDelegateProviding {
    public var ddURLSessionDelegate: DatadogURLSessionDelegate { self }
}
