/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal protocol UIKitRUMViewsHandlerType: class {
    func subscribe(commandsSubscriber: RUMCommandSubscriber)
    func notify_viewWillAppear(viewController: UIViewController, animated: Bool)
    func notify_viewWillDisappear(viewController: UIViewController, animated: Bool)
}

internal class UIKitRUMViewsHandler: UIKitRUMViewsHandlerType {
    private let predicate: UIKitRUMViewsPredicate
    private let dateProvider: DateProvider

    init(predicate: UIKitRUMViewsPredicate, dateProvider: DateProvider) {
        self.predicate = predicate
        self.dateProvider = dateProvider
    }

    // MARK: - UIKitRUMViewsHandlerType

    weak var subscriber: RUMCommandSubscriber?

    func subscribe(commandsSubscriber: RUMCommandSubscriber) {
        self.subscriber = commandsSubscriber
    }

    func notify_viewWillAppear(viewController: UIViewController, animated: Bool) {
        if let rumView = predicate.rumView(for: viewController) {
            subscriber?.process(
                command: RUMStartViewCommand(
                    time: dateProvider.currentDate(),
                    identity: viewController,
                    path: rumView.name,
                    attributes: rumView.attributes
                )
            )
        }
    }

    func notify_viewWillDisappear(viewController: UIViewController, animated: Bool) {
        if let rumView = predicate.rumView(for: viewController) {
            subscriber?.process(
                command: RUMStopViewCommand(
                    time: dateProvider.currentDate(),
                    attributes: rumView.attributes,
                    identity: viewController
                )
            )
        }
    }
}
