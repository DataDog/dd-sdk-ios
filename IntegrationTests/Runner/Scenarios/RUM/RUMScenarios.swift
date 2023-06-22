/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Datadog
import DatadogInternal
import DatadogRUM

/// Scenario which starts a navigation controller. Each view controller pushed to this navigation
/// uses the RUM manual instrumentation API to send RUM events to the server.
final class RUMManualInstrumentationScenario: TestScenario {
    static let storyboardName = "RUMManualInstrumentationScenario"
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

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: Predicate())
            .enableTracing(false)
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

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: Predicate())
            .enableTracing(false)
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

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: Predicate())
            .enableTracing(false)
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

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: Predicate())
            .enableTracing(false)
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

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: Predicate())
            .trackUIKitRUMActions()
            .enableTracing(false)
    }
}

/// Scenario which uses RUM only. Blocks the main thread and expects to have non-zero MobileVitals values
final class RUMMobileVitalsScenario: TestScenario {
    static var storyboardName: String = "RUMMobileVitalsScenario"

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews()
            .trackUIKitRUMActions()
            .trackRUMLongTasks(threshold: 2.5)
            .enableTracing(false)
    }
}

/// Scenario which uses RUM and Tracing auto instrumentation features to track bunch of network requests
/// sent with `URLSession` from two VCs. The first VC calls first party resources, the second one calls third parties.
final class RUMURLSessionResourcesScenario: URLSessionBaseScenario, TestScenario {
    static let storyboardName = "URLSessionScenario"

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews()
            .setRUMResourceAttributesProvider(rumResourceAttributesProvider(request:response:data:error:))

        super.configureSDK(builder: builder) // applies the `trackURLSession(firstPartyHosts:)`
    }
}

/// Scenario which uses RUM and Tracing auto instrumentation features to track bunch of network requests
/// sent with `NSURLSession` from two VCs. The first VC calls first party resources, the second one calls third parties.
final class RUMNSURLSessionResourcesScenario: URLSessionBaseScenario, TestScenario {
    static let storyboardName = "NSURLSessionScenario"

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews()
            .setRUMResourceAttributesProvider(rumResourceAttributesProvider(request:response:data:error:))

        super.configureSDK(builder: builder) // applies the `trackURLSession(firstPartyHosts:)`
    }
}

/// Scenario which uses RUM manual instrumentation API to send bunch of RUM events. Each event contains some
/// "sensitive" information which is scrubbed as configured in `Datadog.Configuration`.
final class RUMScrubbingScenario: TestScenario {
    static var storyboardName: String = "RUMScrubbingScenario"

    func configureSDK(builder: Datadog.Configuration.Builder) {
        func redacted(_ string: String) -> String {
            return string.replacingOccurrences(of: "sensitive", with: "REDACTED")
        }

        _ = builder
            .enableTracing(false)
            .setRUMViewEventMapper { viewEvent in
                var viewEvent = viewEvent
                viewEvent.view.url = redacted(viewEvent.view.url)
                if let viewName = viewEvent.view.name {
                    viewEvent.view.name = redacted(viewName)
                }
                return viewEvent
            }
            .setRUMErrorEventMapper { errorEvent in
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
            .setRUMResourceEventMapper { resourceEvent in
                var resourceEvent = resourceEvent
                resourceEvent.resource.url = redacted(resourceEvent.resource.url)
                if let viewName = resourceEvent.view.name {
                    resourceEvent.view.name = redacted(viewName)
                }
                return resourceEvent
            }
            .setRUMActionEventMapper { actionEvent in
                var actionEvent = actionEvent
                if let targetName = actionEvent.action.target?.name {
                    actionEvent.action.target?.name = redacted(targetName)
                }
                if let viewName = actionEvent.view.name {
                    actionEvent.view.name = redacted(viewName)
                }
                return actionEvent
            }
    }
}


/// Scenario which starts a navigation controller. Each view controller pushed to this navigation
/// uses the RUM manual instrumentation API to send RUM events to the server.
final class RUMStopSessionsScenario: TestScenario {
    static let storyboardName = "RUMStopSessionScenario"
}

@available(iOS 13, *)
/// Scenario which presents `SwiftUI`-based hierarchy and navigates through
/// its views and view controllers.
final class RUMSwiftUIInstrumentationScenario: TestScenario {
    static var storyboardName: String = "RUMSwiftUIInstrumentationScenario"

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

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: Predicate())
            .trackUIKitRUMActions()
            .enableTracing(false)
    }
}

// MARK: - Helpers

private func rumResourceAttributesProvider(
    request: URLRequest,
    response: URLResponse?,
    data: Data?,
    error: Error?
) -> [AttributeKey: AttributeValue]? {
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
    if let data = data {
        responseBodyValue = String(data: data, encoding: .utf8) ?? "<not an UTF-8 data>"
    }
    if let error = error {
        errorDetailsValue = String(describing: error)
    }

    return [
        "response.body.truncated" : responseBodyValue.flatMap { String($0.prefix(128)) },
        "response.headers" : responseHeadersValue,
        "response.error" : errorDetailsValue,
    ]
}
