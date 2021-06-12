/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal protocol UIKitRUMViewsHandlerType: AnyObject {
    func subscribe(commandsSubscriber: RUMCommandSubscriber)
    /// Gets called on `super.viewDidAppear()`.
    func notify_viewDidAppear(viewController: UIViewController, animated: Bool)
    /// Gets called on `super.viewDidDisappear()`.
    func notify_viewDidDisappear(viewController: UIViewController, animated: Bool)
}

internal class UIKitRUMViewsHandler: UIKitRUMViewsHandlerType {
    private let predicate: UIKitRUMViewsPredicate
    private let dateProvider: DateProvider
    private let inspector: UIKitHierarchyInspectorType

    init(
        predicate: UIKitRUMViewsPredicate,
        dateProvider: DateProvider,
        inspector: UIKitHierarchyInspectorType = UIKitHierarchyInspector(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.predicate = predicate
        self.dateProvider = dateProvider
        self.inspector = inspector

        notificationCenter.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    // MARK: - UIKitRUMViewsHandlerType

    weak var subscriber: RUMCommandSubscriber?

    func subscribe(commandsSubscriber: RUMCommandSubscriber) {
        self.subscriber = commandsSubscriber
    }

    func notify_viewDidAppear(viewController: UIViewController, animated: Bool) {
        if let rumView = rumView(for: viewController) {
            startIfNotStarted(rumView: rumView, for: viewController)
        }
    }

    func notify_viewDidDisappear(viewController: UIViewController, animated: Bool) {
        if let topViewController = inspector.topViewController(),
           let rumView = rumView(for: topViewController) {
            startIfNotStarted(rumView: rumView, for: topViewController)
        }
    }

    // MARK: - Private

    @objc
    private func appWillResignActive() {
        stop(viewController: lastStartedViewController)
    }

    @objc
    private func appDidBecomeActive() {
        if let vc = lastStartedViewController,
           let rumView = predicate.rumView(for: vc) {
            start(viewController: vc, rumView: rumView)
        }
    }

    /// The `UIViewController` recently asked in `UIKitRUMViewsPredicate`.
    private weak var recentlyAskedViewController: UIViewController?

    private func rumView(for viewController: UIViewController) -> RUMView? {
        if viewController === recentlyAskedViewController {
            return nil
        }

        recentlyAskedViewController = viewController
        return predicate.rumView(for: viewController)
    }

    /// The `UIViewController` indicating the active `RUMView`.
    private weak var lastStartedViewController: UIViewController?

    private func startIfNotStarted(rumView: RUMView, for viewController: UIViewController) {
        if viewController === lastStartedViewController {
            return
        }

        if subscriber == nil {
            userLogger.warn(
                """
                RUM View was started, but no `RUMMonitor` is registered on `Global.rum`. RUM auto instrumentation will not work.
                Make sure `Global.rum = RUMMonitor.initialize()` is called before any `UIViewController` is presented.
                """
            )
        }

        stop(viewController: lastStartedViewController)
        start(viewController: viewController, rumView: rumView)

        lastStartedViewController = viewController
    }

    private func start(viewController: UIViewController, rumView: RUMView) {
        subscriber?.process(
            command: RUMStartViewCommand(
                time: dateProvider.currentDate(),
                identity: viewController,
                name: rumView.name,
                path: rumView.path,
                attributes: rumView.attributes
            )
        )
    }

    private func stop(viewController: UIViewController?) {
        if let vc = viewController {
            subscriber?.process(
                command: RUMStopViewCommand(
                    time: dateProvider.currentDate(),
                    attributes: [:],
                    identity: vc
                )
            )
        }
    }
}
