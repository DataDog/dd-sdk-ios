/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogInternal

internal final class RUMViewsHandler {
    /// RUM representation of a View.
    private struct View {
        /// The RUM View identity.
        let identity: ViewIdentifier

        /// View name used for RUM Explorer.
        let name: String

        /// View path used for RUM Explorer.
        let path: String

        /// Whether the view is modal, but untracked (should not send start / stop commands)
        let isUntrackedModal: Bool

        /// Custom attributes to attach to the View.
        let attributes: [AttributeKey: AttributeValue]
    }

    /// The current date provider.
    private let dateProvider: DateProvider

    /// `UIKit` view predicate. `nil`, if `UIKit` auto-instrumentations is
    /// disabled.
    private let predicate: UIKitRUMViewsPredicate?

    /// The notification center where this handler observes following `UIApplication` notifications:
    /// - `.didEnterBackgroundNotification`
    /// - `.willEnterForegroundNotification`
    private weak var notificationCenter: NotificationCenter?

    /// The RUM Command subscriber responsible for processing
    /// this publisher's commands.
    internal weak var subscriber: RUMCommandSubscriber?

    /// The appearing views stack.
    ///
    /// This stack allows to track appearing and disappearing views to consistently
    /// publish start and stop commands to the subscriber. The last item of the
    /// stack is the visible one, any items below it have appeared before but not yet
    /// disappeared. Therefore, they are considered not visible but can be revealed
    /// if the last item disappears.
    private var stack: [View] = []

    /// Creates a new `SwiftUI.View` handler to publish RUM view commands.
    /// - Parameters:
    ///   - dateProvider: The current date provider.
    ///   - predicate: `UIKit` view predicate. `nil`, if `UIKit`
    ///     auto-instrumentations is disabled.
    ///   - notificationCenter: The notification center where this handler
    ///    a set of `UIApplication` notifications.
    init(
        dateProvider: DateProvider,
        predicate: UIKitRUMViewsPredicate?,
        notificationCenter: NotificationCenter = .default
    ) {
        self.dateProvider = dateProvider
        self.predicate = predicate
        self.notificationCenter = notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter?.removeObserver(
            self,
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        notificationCenter?.removeObserver(
            self,
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    private func add(view: View) {
        // Ignore the view if it's already visible
        if view.identity == stack.last?.identity {
            return
        }

        // Stop the last appearing view of the stack
        if let current = stack.last {
            stop(view: current)
        }

        if !view.isUntrackedModal {
            // Start the new appearing view
            start(view: view)
        }

        // Add/Move the appearing view to the top
        stack.removeAll(where: { $0.identity == view.identity })
        stack.append(view)
    }

    private func remove(identity: ViewIdentifier) {
        guard identity == stack.last?.identity else {
            // Remove any disappearing view from the stack if
            // it's not visible.
            return stack.removeAll(where: { $0.identity == identity })
        }

        // Stop and remove the visible view from the stack
        let view = stack.removeLast()
        stop(view: view)

        // Restart the previous view if any.
        if let current = stack.last {
            start(view: current)
        }
    }

    private func start(view: View) {
        guard let subscriber = subscriber else {
            return DD.logger.warn(
                """
                RUM View was started, but no `RUMMonitor` is registered on `Global.rum`. RUM instrumentation will not work.
                Make sure `Global.rum = RUMMonitor.initialize()` is called before any view appears.
                """
            )
        }

        guard !view.isUntrackedModal else {
            return
        }

        subscriber.process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: view.identity,
                name: view.name,
                path: view.path,
                attributes: view.attributes
            )
        )
    }

    private func stop(view: View) {
        guard !view.isUntrackedModal else {
            return
        }

        subscriber?.process(
            command: RUMStopViewCommand(
                time: dateProvider.now,
                attributes: [:],
                identity: view.identity
            )
        )
    }

    @objc
    private func applicationDidEnterBackground() {
        if let current = stack.last {
            stop(view: current)
        }
    }

    @objc
    private func applicationWillEnterForeground() {
        if let current = stack.last {
            start(view: current)
        }
    }
}

extension RUMViewsHandler: UIViewControllerHandler {
    func notify_viewDidAppear(viewController: UIViewController, animated: Bool) {
        let identity = ViewIdentifier(viewController)
        if let view = stack.first(where: { $0.identity == identity }) {
            // If the stack already contains the view controller, just restarts the view.
            // This prevents from calling the predicate when unnecessary.
            add(view: view)
        } else if let rumView = predicate?.rumView(for: viewController) {
            add(
                view: .init(
                    identity: identity,
                    name: rumView.name,
                    path: rumView.path ?? viewController.canonicalClassName,
                    isUntrackedModal: rumView.isUntrackedModal,
                    attributes: rumView.attributes
                )
            )
        } else if #available(iOS 13, tvOS 13, *), viewController.isModalInPresentation {
            add(
                view: .init(
                    identity: identity,
                    name: "RUMUntrackedModal",
                    path: viewController.canonicalClassName,
                    isUntrackedModal: true,
                    attributes: [:]
                )
            )
        }
    }

    func notify_viewDidDisappear(viewController: UIViewController, animated: Bool) {
        remove(identity: ViewIdentifier(viewController))
    }
}

extension RUMViewsHandler: SwiftUIViewHandler {
    /// Respond to a `SwiftUI.View.onAppear` event.
    ///
    /// - Parameters:
    ///   - key: The appearing `SwiftUI.View` key.
    ///   - name: The appearing `SwiftUI.View` name.
    ///   - attributes: The appearing `SwiftUI.View` attributes.
    func notify_onAppear(identity: String, name: String, path: String, attributes: [AttributeKey: AttributeValue]) {
        add(
            view: .init(
                identity: ViewIdentifier(identity),
                name: name,
                path: path,
                isUntrackedModal: false,
                attributes: attributes
            )
        )
    }

    /// Respond to a `SwiftUI.View.onDisappear` event.
    ///
    /// - Parameter key: The disappearing `SwiftUI.View` key.
    func notify_onDisappear(identity: String) {
        remove(identity: ViewIdentifier(identity))
    }
}
