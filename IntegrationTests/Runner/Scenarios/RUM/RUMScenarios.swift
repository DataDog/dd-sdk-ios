/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogRUM
import DatadogCore

/// Scenario which starts a navigation controller. Each view controller pushed to this navigation
/// uses the RUM manual instrumentation API to send RUM events to the server.
final class RUMManualInstrumentationScenario: TestScenario {
    static let storyboardName = "RUMManualInstrumentationScenario"

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        RUM.enable(with: config)
    }
}

/// Scenario which starts a navigation controller and runs through 4 different view controllers by navigating
/// back and forth. Tracks view controllers as RUM Views.
final class RUMNavigationControllerScenario: TestScenario {
    static let storyboardName = "RUMNavigationControllerScenario"

    private class Predicate: UIKitRUMViewsPredicate {
        func rumView(for viewController: UIViewController) -> RUMView? {
            switch viewController.accessibilityLabel {
            case "Screen 1":
                return .init(name: "Screen1")
            case "Screen 2":
                return .init(name: "Screen2")
            case "Screen 3":
                return .init(name: "Screen3")
            case "Screen 4":
                return .init(name: "Screen4")
            default:
                return nil
            }
        }
    }

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.uiKitViewsPredicate = Predicate()
        RUM.enable(with: config)
    }
}

/// Scenario which presents `UITabBarController`-based hierarchy and navigates through
/// its view controllers. Tracks view controllers as RUM Views.
final class RUMTabBarAutoInstrumentationScenario: TestScenario {
    static var storyboardName: String = "RUMTabBarAutoInstrumentationScenario"

    private class Predicate: UIKitRUMViewsPredicate {
        func rumView(for viewController: UIViewController) -> RUMView? {
            if let viewName = viewController.accessibilityLabel {
                return .init(name: viewName)
            } else {
                return nil
            }
        }
    }

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.uiKitViewsPredicate = Predicate()
        RUM.enable(with: config)
    }
}

/// Scenario based on `UINavigationController` hierarchy, which presents different VCs modally.
/// Tracks view controllers as RUM Views.
final class RUMModalViewsAutoInstrumentationScenario: TestScenario {
    static var storyboardName: String = "RUMModalViewsAutoInstrumentationScenario"

    private class Predicate: UIKitRUMViewsPredicate {
        func rumView(for viewController: UIViewController) -> RUMView? {
            if let viewName = viewController.accessibilityLabel {
                return .init(name: viewName)
            } else {
                return nil
            }
        }
    }

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.uiKitViewsPredicate = Predicate()
        RUM.enable(with: config)
    }
}

/// Scenario based on `UINavigationController` hierarchy, which presents different VCs modally.
/// Tracks view controllers as RUM Views.
final class RUMUntrackedModalViewsAutoInstrumentationScenario: TestScenario {
    static var storyboardName: String = "RUMModalViewsAutoInstrumentationScenario"

    private class Predicate: UIKitRUMViewsPredicate {
        func rumView(for viewController: UIViewController) -> RUMView? {
            if let viewName = viewController.accessibilityLabel {
                if viewController.modalPresentationStyle == .fullScreen {
                    if #available(iOS 13, tvOS 13, *) {
                        // Untracked on iOS/tvOS 13+ via isModalInPresentation
                        return nil
                    } else {
                        return .init(name: viewName, isUntrackedModal: true)
                    }
                }
                return .init(name: viewName)
            } else {
                return nil
            }
        }
    }

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.uiKitViewsPredicate = Predicate()
        RUM.enable(with: config)
    }
}

/// Scenario which interacts with various interactive elements laid between different view controllers,
/// including `UITableViewController` and `UICollectionViewController`. Tapped views
/// and controls are tracked as RUM Actions.
final class RUMTapActionScenario: TestScenario {
    static var storyboardName: String = "RUMTapActionScenario"

    private class Predicate: UIKitRUMViewsPredicate {
        func rumView(for viewController: UIViewController) -> RUMView? {
            switch NSStringFromClass(type(of: viewController)) {
            case "Runner.RUMTASScreen1ViewController":
                return .init(name: "MenuView")
            case "Runner.RUMTASTableViewController":
                return .init(name: "TableView")
            case "Runner.RUMTASCollectionViewController":
                return .init(name: "CollectionView")
            case "Runner.RUMTASVariousUIControllsViewController":
                return .init(name: "UIControlsView")
            default:
                return nil
            }
        }
    }

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.uiKitViewsPredicate = Predicate()
        config.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        RUM.enable(with: config)
    }
}

/// Scenario which uses RUM only. Blocks the main thread and expects to have non-zero MobileVitals values
final class RUMMobileVitalsScenario: TestScenario {
    static var storyboardName: String = "RUMMobileVitalsScenario"

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        config.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        config.longTaskThreshold = 2.5
        RUM.enable(with: config)
    }
}

/// Base scenario for RUM resources testing.
class RUMResourcesBaseScenario: URLSessionBaseScenario {
    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()

        switch setup.instrumentationMethod {
        case .legacyWithFeatureFirstPartyHosts, .legacyInheritance, .legacyComposition, .delegateUsingFeatureFirstPartyHosts:
            config.urlSessionTracking = .init(
                firstPartyHostsTracing: .trace(
                    hosts: [
                        customGETResourceURL.host!,
                        customPOSTRequest.url!.host!,
                        badResourceURL.host!,
                    ],
                    sampleRate: 100
                ),
                resourceAttributesProvider: rumResourceAttributesProvider(request:response:data:error:)
            )
        case .legacyWithAdditionalFirstyPartyHosts, .delegateWithAdditionalFirstyPartyHosts:
            config.urlSessionTracking = .init(
                firstPartyHostsTracing: .trace(hosts: [], sampleRate: 100), // hosts will be set through `DDURLSessionDelegate`
                resourceAttributesProvider: rumResourceAttributesProvider(request:response:data:error:)
            )
        }
        RUM.enable(with: config)
    }
}

/// Scenario which uses RUM resources instrumentation to track bunch of network requests
/// sent with Swift `URLSession` from two VCs. The first VC calls first party resources, the second one calls third parties.
final class RUMURLSessionResourcesScenario: RUMResourcesBaseScenario, TestScenario {
    static let storyboardName = "URLSessionScenario"
}

/// Scenario which uses RUM resources instrumentation to track bunch of network requests
/// sent with Objective-c `NSURLSession` from two VCs. The first VC calls first party resources, the second one calls third parties.
final class RUMNSURLSessionResourcesScenario: RUMResourcesBaseScenario, TestScenario {
    static let storyboardName = "NSURLSessionScenario"
}

/// Scenario which uses RUM manual instrumentation API to send bunch of RUM events. Each event contains some
/// "sensitive" information which is scrubbed as configured in `Datadog.Configuration`.
final class RUMScrubbingScenario: TestScenario {
    static var storyboardName: String = "RUMScrubbingScenario"

    func configureFeatures() {
        func redacted(_ string: String) -> String {
            return string.replacingOccurrences(of: "sensitive", with: "REDACTED")
        }

        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.viewEventMapper = { viewEvent in
            var viewEvent = viewEvent
            viewEvent.view.url = redacted(viewEvent.view.url)
            if let viewName = viewEvent.view.name {
                viewEvent.view.name = redacted(viewName)
            }
            return viewEvent
        }
        config.errorEventMapper = { errorEvent in
            var errorEvent = errorEvent
            errorEvent.error.message = redacted(errorEvent.error.message)
            errorEvent.view.url = redacted(errorEvent.view.url)
            if let viewName = errorEvent.view.name {
                errorEvent.view.name = redacted(viewName)
            }
            if let resourceURL = errorEvent.error.resource?.url {
                errorEvent.error.resource?.url = redacted(resourceURL)
            }
            if let errorStack = errorEvent.error.stack {
                errorEvent.error.stack = redacted(errorStack)
            }
            return errorEvent
        }
        config.resourceEventMapper = { resourceEvent in
            var resourceEvent = resourceEvent
            resourceEvent.resource.url = redacted(resourceEvent.resource.url)
            if let viewName = resourceEvent.view.name {
                resourceEvent.view.name = redacted(viewName)
            }
            return resourceEvent
        }
        config.actionEventMapper = { actionEvent in
            var actionEvent = actionEvent
            if let targetName = actionEvent.action.target?.name {
                actionEvent.action.target?.name = redacted(targetName)
            }
            if let viewName = actionEvent.view.name {
                actionEvent.view.name = redacted(viewName)
            }
            return actionEvent
        }
        RUM.enable(with: config)
    }
}


/// Scenario which starts a navigation controller. Each view controller pushed to this navigation
/// uses the RUM manual instrumentation API to send RUM events to the server.
final class RUMStopSessionsScenario: TestScenario {
    static let storyboardName = "RUMStopSessionScenario"

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        RUM.enable(with: config)
    }
}

@available(iOS 13, *)
/// Scenario which presents `SwiftUI`-based hierarchy and navigates through
/// its views and view controllers.
final class RUMSwiftUIManualInstrumentationScenario: TestScenario {
    static var storyboardName: String = "RUMSwiftUIManualInstrumentationScenario"

    private class Predicate: UIKitRUMViewsPredicate {
        let `default` = DefaultUIKitRUMViewsPredicate()

        func rumView(for viewController: UIViewController) -> RUMView? {
            if viewController is SwiftUIRootViewController {
                return nil
            }

            if let viewController = viewController as? UIScreenViewController {
                return .init(name: "UIKit View \(viewController.index)")
            }

            return `default`.rumView(for: viewController)
        }
    }

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.uiKitViewsPredicate = Predicate()
        config.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        RUM.enable(with: config)
    }
}

// MARK: SwiftUI Auto-instrumentation
/// Scenarios which presents `SwiftUI`-based hierarchies and navigate through its views.
/// It uses the RUM Swift auto-instrumentation (or mixed instrumentations).

/// 1. Single hosting controller root view.
@available(iOS 16.0, *)
final class RUMSwiftUIAutoInstrumentationSingleRootViewScenario: TestScenario {
    static var storyboardName: String = "RUMSwiftUIAutoInstrumentationSingleRootViewScenario"

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.swiftUIViewsPredicate = SwiftUIPredicate()
        config.swiftUIActionsPredicate = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true)
        config.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        RUM.enable(with: config)
    }
}

/// 2. Tabbar root view and multiple navigation scenario in each tab.
@available(iOS 13, *)
final class RUMSwiftUIAutoInstrumentationRootTabbarScenario: TestScenario {
    static var storyboardName: String = "RUMSwiftUIAutoInstrumentationRootTabbarScenario"

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.swiftUIViewsPredicate = SwiftUIPredicate()
        config.swiftUIActionsPredicate = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true)
        RUM.enable(with: config)
    }
}

/// 3. Single view with multiple action targets.
@available(iOS 13, *)
final class RUMSwiftUIAutoInstrumentationActionViewScenario: TestScenario {
    static var storyboardName: String = "RUMSwiftUIAutoInstrumentationActionViewScenario"

    func configureFeatures() {
        var config = RUM.Configuration(applicationID: "rum-application-id")
        config.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        config.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        config.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        config.swiftUIViewsPredicate = SwiftUIPredicate()
        config.swiftUIActionsPredicate = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true)
        RUM.enable(with: config)
    }
}

// TODO: RUM-9888 - Manual + Auto instrumentation scenario

// MARK: - Helpers

private class SwiftUIPredicate: SwiftUIRUMViewsPredicate {
    let `default` = DefaultSwiftUIRUMViewsPredicate()

    func rumView(for extractedViewName: String) -> DatadogRUM.RUMView? {
        if extractedViewName == "RUMSessionEndView" {
            return nil
        }

        return RUMView(name: extractedViewName)
    }
}

private func rumResourceAttributesProvider(
    request: URLRequest,
    response: URLResponse?,
    data: Data?,
    error: Error?
) -> [String: Encodable]? {
    /// Apples new-line separated text format to  response headers.
    func format(headers: [AnyHashable: Any]) -> String {
        var formattedHeaders: [String] = []
        headers.forEach { key, value in
            formattedHeaders.append("\(String(describing: key)): \(String(describing: value))")
        }
        return formattedHeaders.joined(separator: "\n")
    }

    var responseBodyValue: String?
    var responseHeadersValue: String?
    var errorDetailsValue: String?

    if let responseHeaders = (response as? HTTPURLResponse)?.allHeaderFields {
        responseHeadersValue = format(headers: responseHeaders)
    }
    if let error = error {
        errorDetailsValue = String(describing: error)
    } else {
        responseBodyValue = String(data: data ?? .init(), encoding: .utf8) ?? "<not an UTF-8 data>"
    }

    return [
        "response.body.truncated" : responseBodyValue.flatMap { String($0.prefix(128)) },
        "response.headers" : responseHeadersValue,
        "response.error" : errorDetailsValue,
    ]
}
