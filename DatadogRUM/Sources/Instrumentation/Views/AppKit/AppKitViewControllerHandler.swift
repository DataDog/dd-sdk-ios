/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

internal protocol NSViewControllerHandler: RUMCommandPublisher {
    /// Gets called on `super.viewDidAppear()`.
    func notify_viewDidAppear(viewController: DDViewController)
    /// Gets called on `super.viewDidDisappear()`.
    func notify_viewDidDisappear(viewController: DDViewController)
}
#endif
