/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog
import UIKit

// MARK: - TestScenario interface

protocol TestScenario {
    /// The name of the storyboard containing this scenario.
    static var storyboardName: String { get }

    /// Applies additional SDK configuration for running this scenario.
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
    case TracingManualInstrumentationScenario.envIdentifier():
        return TracingManualInstrumentationScenario()
    case TracingURLSessionScenario.envIdentifier():
        return TracingURLSessionScenario()
    case TracingNSURLSessionScenario.envIdentifier():
        return TracingNSURLSessionScenario()
    case RUMManualInstrumentationScenario.envIdentifier():
        return RUMManualInstrumentationScenario()
    case RUMNavigationControllerScenario.envIdentifier():
        return RUMNavigationControllerScenario()
    case RUMTabBarAutoInstrumentationScenario.envIdentifier():
        return RUMTabBarAutoInstrumentationScenario()
    case RUMTapActionScenario.envIdentifier():
        return RUMTapActionScenario()
    default:
        fatalError("Cannot find `TestScenario` for `envIdentifier`: \(envIdentifier)")
    }
}

// MARK: - Logging Test Scenarios

/// Scenario which starts a view controller that sends bunch of logs to the server.
struct LoggingScenario: TestScenario {
    static let storyboardName = "LoggingScenario"
}

// MARK: - Tracing Test Scenarios

/// Scenario which starts a view controller that sends bunch of spans using manual API of `Tracer`.
/// It also uses the `span.log()` to send logs.
struct TracingManualInstrumentationScenario: TestScenario {
    static let storyboardName = "TracingManualInstrumentationScenario"
}

/// Scenario which uses Tracing auto instrumentation feature to track bunch of network requests
/// sent with `URLSession` (Swift).
class TracingURLSessionScenario: _TracingURLSessionBaseScenario, TestScenario {
    static let storyboardName = "TracingURLSessionScenario"

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        super.configureSDK(builder: builder)
    }
}

/// Scenario which uses Tracing auto instrumentation feature to track bunch of network requests
/// sent with `NSURLSession` (Objective-C).
@objc
class TracingNSURLSessionScenario: _TracingURLSessionBaseScenario, TestScenario {
    static let storyboardName = "TracingNSURLSessionScenario"

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        super.configureSDK(builder: builder)
    }
}

/// Base scenario for both `URLSession` and `NSURLSession` scenarios.
/// It makes both Swift and Objective-C tests share the same endpoints and SDK configuration.
@objc
class _TracingURLSessionBaseScenario: NSObject {
    /// The URL to custom GET resource, observed by Tracing auto instrumentation.
    @objc
    let customGETResourceURL: URL
    /// The `URLRequest` to custom POST resource,  observed by Tracing auto instrumentation.
    @objc
    let customPOSTRequest: URLRequest
    /// An unresolvable URL to fake resource DNS resolution error,  observed by Tracing auto instrumentation.
    @objc
    let badResourceURL: URL

    override init() {
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

// MARK: - RUM Test Scenarios

/// Scenario which starts a navigation controller. Each view controller pushed to this navigation
/// uses the RUM manual instrumentation API to send RUM events to the server.
struct RUMManualInstrumentationScenario: TestScenario {
    static let storyboardName = "RUMManualInstrumentationScenario"
}

/// Scenario which starts a navigation controller and runs through 4 different view controllers by navigating
/// back and forth. Tracks view controllers as RUM Views.
struct RUMNavigationControllerScenario: TestScenario {
    static let storyboardName = "RUMNavigationControllerScenario"

    private class Predicate: UIKitRUMViewsPredicate {
        func rumView(for viewController: UIViewController) -> RUMViewFromPredicate? {
            switch viewController.accessibilityLabel {
            case "Screen 1":
                return .init(path: "Screen1")
            case "Screen 2":
                return .init(path: "Screen2")
            case "Screen 3":
                return .init(path: "Screen3")
            case "Screen 4":
                return .init(path: "Screen4")
            default:
                return nil
            }
        }
    }

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: Predicate())
            .enableLogging(false)
            .enableTracing(false)
    }
}

/// Scenario which presents `UITabBarController`-based hierarchy and navigates through
/// its view controllers. Tracks view controllers as RUM Views.
struct RUMTabBarAutoInstrumentationScenario: TestScenario {
    static var storyboardName: String = "RUMTabBarAutoInstrumentationScenario"

    private class Predicate: UIKitRUMViewsPredicate {
        func rumView(for viewController: UIViewController) -> RUMViewFromPredicate? {
            if let viewName = viewController.accessibilityLabel {
                return .init(path: viewName)
            } else {
                return nil
            }
        }
    }

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: Predicate())
            .enableLogging(false)
            .enableTracing(false)
    }
}

/// Scenario which interacts with various interactive elements laid between different view controllers,
/// including `UITableViewController` and `UICollectionViewController`. Tapped views
/// and controls are tracked as RUM Actions.
struct RUMTapActionScenario: TestScenario {
    static var storyboardName: String = "RUMTapActionScenario"

    private class Predicate: UIKitRUMViewsPredicate {
        func rumView(for viewController: UIViewController) -> RUMViewFromPredicate? {
            switch NSStringFromClass(type(of: viewController)) {
            case "Example.RUMTASScreen1ViewController":
                return .init(path: "MenuViewController")
            case "Example.RUMTASTableViewController":
                return .init(path: "TableViewController")
            case "Example.RUMTASCollectionViewController":
                return .init(path: "CollectionViewController")
            case "Example.RUMTASVariousUIControllsViewController":
                return .init(path: "UIControlsViewController")
            default:
                return nil
            }
        }
    }

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: Predicate())
            .trackUIKitActions(true)
            .enableLogging(false)
            .enableTracing(false)
    }
}
