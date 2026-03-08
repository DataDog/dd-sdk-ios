/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal protocol UIViewControllerHandler: RUMCommandPublisher, Sendable {
    /// Gets called on `super.viewDidAppear()`. Always on the main thread.
    @MainActor
    func notify_viewDidAppear(viewController: UIViewController, animated: Bool)
    /// Gets called on `super.viewDidDisappear()`. Always on the main thread.
    @MainActor
    func notify_viewDidDisappear(viewController: UIViewController, animated: Bool)
}
