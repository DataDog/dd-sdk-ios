/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal protocol UIViewControllerHandler: RUMCommandPublisher {
    /// Gets called on `super.viewDidAppear()`.
    func notify_viewDidAppear(viewController: UIViewController, animated: Bool)
    /// Gets called on `super.viewDidDisappear()`.
    func notify_viewDidDisappear(viewController: UIViewController, animated: Bool)
}
