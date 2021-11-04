/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

/// Publisher generating RUM Commands on `SwiftUI.View` events.
internal protocol SwiftUIViewHandler: RUMCommandPublisher {
    /// Respond to a `SwiftUI.View.onAppear` event.
    func onAppear(identity: String, name: String, path: String, attributes: [AttributeKey: AttributeValue])

    /// Respond to a `SwiftUI.View.onDisappear` event.
    func onDisappear(identity: String)
}

internal final class SwiftUIRUMViewsHandler: SwiftUIViewHandler {
    /// RUM representation of a `SwiftUI.View`.
    private struct View {
        /// The RUM View identity.
        let identity: String

        /// View name used for RUM Explorer.
        let name: String

        /// View path used for RUM Explorer.
        let path: String

        /// Custom attributes to attach to the View.
        let attributes: [AttributeKey: AttributeValue]
    }

    /// The current date provider.
    private let dateProvider: DateProvider

    /// The notification center where this handler observe the following notifications:
    /// - `UIApplicationDidEnterBackgroundNotification`
    /// - `UIApplicationWillEnterForegroundNotification`
    private weak var notificationCenter: NotificationCenter?

    /// The RUM Command subscriber responsible for processing
    /// this publisher's commands.
    private weak var subscriber: RUMCommandSubscriber?

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
    ///   - notificationCenter: The notification center where this handler
    ///    a set of `UIApplication` notifications.
    init(
        dateProvider: DateProvider,
        notificationCenter: NotificationCenter = .default
    ) {
        self.dateProvider = dateProvider
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

    /// Respond to a `SwiftUI.View.onAppear` event.
    ///
    /// - Parameters:
    ///   - identity: The appearing `SwiftUI.View` identity.
    ///   - name: The appearing `SwiftUI.View` name.
    ///   - attributes: The appearing `SwiftUI.View` attributes.
    func onAppear(identity: String, name: String, path: String, attributes: [AttributeKey: AttributeValue]) {
        // Ignore the view if it's already visible
        if stack.last?.identity == identity {
            return
        }

        // Stop the last appearing view of the stack
        if let current = stack.last {
            stop(view: current)
        }

        let view = View(
            identity: identity,
            name: name,
            path: path,
            attributes: attributes
        )

        // Start the new appearing view
        start(view: view)
        // Add/Move the appearing view to the top
        stack.removeAll(where: { $0.identity == identity })
        stack.append(view)
    }

    /// Respond to a `SwiftUI.View.onDisappear` event.
    ///
    /// - Parameter identity: The disappearing `SwiftUI.View` identity.
    func onDisappear(identity: String) {
        guard stack.last?.identity == identity else {
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
            return userLogger.warn(
                """
                RUM View was started, but no `RUMMonitor` is registered on `Global.rum`. RUM instrumentation will not work.
                Make sure `Global.rum = RUMMonitor.initialize()` is called before any `SwiftUI.View` appears.
                """
            )
        }

        subscriber.process(
            command: RUMStartViewCommand(
                time: dateProvider.currentDate(),
                identity: view.identity,
                name: view.name,
                path: view.path,
                attributes: view.attributes
            )
        )
    }

    private func stop(view: View) {
        subscriber?.process(
            command: RUMStopViewCommand(
                time: dateProvider.currentDate(),
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
