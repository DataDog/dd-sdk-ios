/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog

let allRUMScenarios: [TestScenario.Type] = [
    RUMManualInstrumentationScenario.self,
    RUMNavigationControllerScenario.self,
    RUMTabBarAutoInstrumentationScenario.self,
    RUMModalViewsAutoInstrumentationScenario.self,
    RUMTapActionScenario.self,
    RUMResourcesScenario.self,
]

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
        func rumView(for viewController: UIViewController) -> RUMView? {
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
        func rumView(for viewController: UIViewController) -> RUMView? {
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

/// Scenario based on `UINavigationController` hierarchy, which presents different VCs modally.
/// Tracks view controllers as RUM Views.
struct RUMModalViewsAutoInstrumentationScenario: TestScenario {
    static var storyboardName: String = "RUMModalViewsAutoInstrumentationScenario"

    private class Predicate: UIKitRUMViewsPredicate {
        func rumView(for viewController: UIViewController) -> RUMView? {
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
        func rumView(for viewController: UIViewController) -> RUMView? {
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

/// Scenario which uses RUM and Tracing auto instrumentation features to track bunch of network requests
/// sent with `URLSession` from two VCs. The first VC calls first party resources, the second one calls third parties.
final class RUMResourcesScenario: URLSessionBaseScenario, TestScenario {
    static let storyboardName = "URLSessionScenario"
    static func envIdentifier() -> String { "RUMResourcesScenario" }

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: DefaultUIKitRUMViewsPredicate())

        super.configureSDK(builder: builder) // applies the `track(firstPartyHosts:)`
    }
}
