/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

/// Base scenario for `URLSession` and `NSURLSession` instrumentation.  It makes
/// both Swift and Objective-C tests share the same endpoints and SDK configuration.
///
/// This scenario presents two view controllers. First sends requests for first party resources, the second
/// calls third party endpoints.
@objc
class URLSessionBaseScenario: NSObject {
    /// Randomizes the way of passing additional first party hosts.
    /// If `true`, instrumented endpoints are passed to `DDURLSessionDelegate`; otherwise, they are passed to `DatadogConfiguration.trackURLSession(...)`.
    private let feedAdditionalFirstyPartyHosts: Bool

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
        feedAdditionalFirstyPartyHosts = .random()
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
        if feedAdditionalFirstyPartyHosts {
            _ = builder.trackURLSession()
        } else {
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
        let delegate: DDURLSessionDelegate
        if feedAdditionalFirstyPartyHosts {
            delegate = DDURLSessionDelegate(
                additionalFirstPartyHosts: [
                    customGETResourceURL.host!,
                    customPOSTRequest.url!.host!,
                    badResourceURL.host!
                ]
            )
        } else {
            delegate = DDURLSessionDelegate()
        }
        return URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
    }
}
