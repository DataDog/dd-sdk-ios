/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

// MARK: - TestScenario interface

protocol TestScenario {
    /// The name of the storyboard containing this scenario.
    static var storyboardName: String { get }

    /// Applies eventual SDK configuration for running this scenario.
    /// Defaults to no-op.
    func configureSDK(builder: Datadog.Configuration.Builder)

    /// An identifier for this scenario used to pass its reference in environment variable.
    /// Defaults to `storyboardName`.
    static func envIdentifier() -> String
}

/// Defaults.
extension TestScenario {
    static func envIdentifier() -> String { storyboardName }
    func configureSDK(builder: Datadog.Configuration.Builder) { /* no-op */ }
}

/// Returns `TestScenario` for given env identifier.
/// Must be updated with every new scenario added.
func createTestScenario(for envIdentifier: String) -> TestScenario {
    switch envIdentifier {
    case LoggingScenario.envIdentifier():
        return LoggingScenario()
    case TracingScenario.envIdentifier():
        return TracingScenario()
    case RUMManualInstrumentationScenario.envIdentifier():
        return RUMManualInstrumentationScenario()
    default:
        fatalError("Cannot find `TestScenario` for `envIdentifier`: \(envIdentifier)")
    }
}

// MARK: - Concrete test scenarios

/// Scenario which starts a view controller that sends bunch of logs to the server.
struct LoggingScenario: TestScenario {
    static let storyboardName = "LoggingScenario"
}

/// Scenario which starts a view controller that sends bunch of spans to the server. It uses
/// the `span.log()` to send logs. It also tracks resources send to specified URLs
/// by using tracing auto instrumentation feature.
struct TracingScenario: TestScenario {
    static let storyboardName = "TracingScenario"

    /// The URL to custom GET resource, observed by Tracing auto instrumentation.
    let customGETResourceURL: URL
    /// The `URLRequest` to custom POST resource,  observed by Tracing auto instrumentation.
    let customPOSTRequest: URLRequest
    /// An unresolvable URL to fake resource DNS resolution error,  observed by Tracing auto instrumentation.
    let badResourceURL: URL

    init() {
        if ProcessInfo.processInfo.arguments.contains("IS_RUNNING_UI_TESTS") {
            let customURL = Environment.customEndpointURL()!
            customGETResourceURL = URL(string: customURL.deletingLastPathComponent().absoluteString + "inspect")!
            customPOSTRequest = {
                var request = URLRequest(url: customURL)
                request.httpMethod = "POST"
                request.addValue("dataTaskWithRequest", forHTTPHeaderField: "creation-method")
                return request
            }()
            badResourceURL = URL(string: "https://foo.bar")!
        } else {
            customGETResourceURL = URL(string: "https://status.datadoghq.com")!
            customPOSTRequest = {
                var request = URLRequest(url: URL(string: "https://status.datadoghq.com/bad/path")!)
                request.httpMethod = "POST"
                request.addValue("dataTaskWithRequest", forHTTPHeaderField: "creation-method")
                return request
            }()
            badResourceURL = URL(string: "https://foo.bar")!
        }
    }

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .set(tracedHosts: [customGETResourceURL.host!, customPOSTRequest.url!.host!, badResourceURL.host!])
    }
}

/// Scenario which starts a navigation controller. Each view controller pushed to this navigation
/// uses the RUM manual instrumentation API to send RUM events to the server.
struct RUMManualInstrumentationScenario: TestScenario {
    static let storyboardName = "RUMManualInstrumentationScenario"
}
