/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

/// An example of instrumenting existing `URLSessionDelegate` with `DDURLSessionDelegate` through inheritance.
private class InheritedURLSessionDelegate: DDURLSessionDelegate {
    override func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        super.urlSession(session, task: task, didCompleteWithError: error) // forward to DD
        /* run custom logic */
    }
}

/// An example of instrumenting existing `URLSessionDelegate` with `DDURLSessionDelegate` through composition.
private class CompositedURLSessionDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, __URLSessionDelegateProviding {
    // MARK: - __URLSessionDelegateProviding conformance
    let ddURLSessionDelegate = DDURLSessionDelegate()

    // MARK: - __URLSessionDelegateProviding handling

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        ddURLSessionDelegate.urlSession(session, task: task, didFinishCollecting: metrics) // forward to DD
        /* run custom logic */
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        ddURLSessionDelegate.urlSession(session, task: task, didCompleteWithError: error) // forward to DD
        /* run custom logic */
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        ddURLSessionDelegate.urlSession(session, dataTask: dataTask, didReceive: data) // forward to DD
        /* run custom logic */
    }
}

/// Base scenario for `URLSession` and `NSURLSession` instrumentation.  It makes
/// both Swift and Objective-C tests share the same endpoints and SDK configuration.
///
/// This scenario presents two view controllers. First sends requests for first party resources, the second
/// calls third party endpoints.
@objc
class URLSessionBaseScenario: NSObject {
    /// The method of instrumenting `URLSession` with `DDURLSessionDelegate`
    private enum InstrumentationMethod: CaseIterable {
        /// Use `DDURLSessionDelegate` directly and
        /// use `firstPartyHosts` defined at SDK level (with `DatadogConfiguration.trackURLSession(firstPartyHosts:)`).
        case directWithGlobalFirstPartyHosts
        /// Use `DDURLSessionDelegate` directly and
        /// use additional `firstPartyHosts` defined when instantiating delegate.
        case directWithAdditionalFirstyPartyHosts
        /// Use `DDURLSessionDelegate` through inheritance (see: `InheritedURLSessionDelegate`).
        case inheritance
        /// Use `DDURLSessionDelegate` through composition (see: `CompositedURLSessionDelegate`).
        case composition
    }

    private let instrumentationMethod: InstrumentationMethod

    /// Randomizes the way of creating `URLSession` instrumented with `DDURLSessionDelegate`.
    /// If `true`, the session is created after `Datadog.initialize()`; if `false`, it's created before.
    private let lazyInitURLSession: Bool

    /// The URL to custom GET resource, observed by Tracing auto instrumentation.
    @objc
    let customGETResourceURL: URL

    /// The `URLRequest` to custom POST resource,  observed by Tracing auto instrumentation.
    @objc
    let customPOSTRequest: URLRequest

    /// An unresolvable URL to fake resource DNS resolution error,  observed by Tracing auto instrumentation.
    @objc
    let badResourceURL: URL

    /// The `URLRequest` to fake 3rd party resource. As it's 3rd party, it won't be observed by Tracing auto instrumentation.
    @objc
    let thirdPartyRequest: URLRequest

    /// The `URL` to fake 3rd party resource. As it's 3rd party, it won't be observed by Tracing auto instrumentation.
    @objc
    let thirdPartyURL: URL

    /// Randomized value determining if the `DDURLSessionDelegate` should be initialized before (`false)` or after `Datadog.initialize()` (`true`).
    private var ddURLSessionDelegate: DDURLSessionDelegate?

    override init() {
        instrumentationMethod = InstrumentationMethod.allCases.randomElement()!
        lazyInitURLSession = .random()

        if ProcessInfo.processInfo.arguments.contains("IS_RUNNING_UI_TESTS") {
            let serverMockConfiguration = Environment.serverMockConfiguration()!
            customGETResourceURL = serverMockConfiguration.instrumentedEndpoints[0]
            customPOSTRequest = {
                var request = URLRequest(url: serverMockConfiguration.instrumentedEndpoints[1])
                request.httpMethod = "POST"
                return request
            }()
            badResourceURL = serverMockConfiguration.instrumentedEndpoints[2]
            thirdPartyURL = serverMockConfiguration.instrumentedEndpoints[3]
            thirdPartyRequest = {
                var request = URLRequest(url: serverMockConfiguration.instrumentedEndpoints[4])
                request.httpMethod = "POST"
                return request
            }()
        } else {
            customGETResourceURL = URL(string: "https://status.datadoghq.com")!
            customPOSTRequest = {
                var request = URLRequest(url: URL(string: "https://status.datadoghq.com/bad/path")!)
                request.httpMethod = "POST"
                request.addValue("dataTaskWithRequest", forHTTPHeaderField: "creation-method")
                return request
            }()
            badResourceURL = URL(string: "https://foo.bar")!
            thirdPartyURL = URL(string: "https://www.bitrise.io")!
            thirdPartyRequest = {
                var request = URLRequest(url: URL(string: "https://www.bitrise.io/about")!)
                request.httpMethod = "POST"
                return request
            }()
        }
        super.init()

        if lazyInitURLSession {
            self.session = nil // it will be created on lazily, on first access from VC
        } else {
            self.session = createInstrumentedURLSession()
        }
    }

    func configureSDK(builder: Datadog.Configuration.Builder) {
        switch instrumentationMethod {
        case .directWithAdditionalFirstyPartyHosts:
            _ = builder.trackURLSession()
        case .directWithGlobalFirstPartyHosts, .inheritance, .composition:
            _ = builder.trackURLSession(
                firstPartyHosts: [customGETResourceURL.host!, customPOSTRequest.url!.host!, badResourceURL.host!]
            )
        }
    }

    private var session: URLSession!

    @objc
    func getURLSession() -> URLSession {
        if session == nil {
            precondition(lazyInitURLSession, "The session is unavailable, but it is not configured for lazy init")
            session = createInstrumentedURLSession()
        }
        return session
    }

    private func createInstrumentedURLSession() -> URLSession {
        let delegate: URLSessionDelegate

        switch instrumentationMethod {
        case .directWithGlobalFirstPartyHosts:
            delegate = DDURLSessionDelegate()
        case .directWithAdditionalFirstyPartyHosts:
            delegate = DDURLSessionDelegate(
                additionalFirstPartyHostsWithHeaderTypes: [
                    customGETResourceURL.host,
                    customPOSTRequest.url?.host,
                    badResourceURL.host
                ]
                .compactMap { $0 }
                .reduce(into: [:], { partialResult, value in
                    partialResult[value] = [.datadog] // Prevents duplicates
                })
            )
        case .inheritance:
            delegate = InheritedURLSessionDelegate()
        case .composition:
            delegate = CompositedURLSessionDelegate()
        }

        return URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
    }
}
