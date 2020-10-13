/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

/// Inspects the view controllers hierarchy of the current window and finds
/// the `UIViewController` which is currently displayed to the user.
internal protocol UIKitHierarchyInspectorType {
    /// The top-most `UIViewController` currently displayed to the user.
    func topViewController() -> UIViewController?
}

internal struct UIKitHierarchyInspector: UIKitHierarchyInspectorType {
    private let rootViewControllerProvider: () -> UIViewController?

    init(
        rootViewControllerProvider: @escaping () -> UIViewController? = {
            UIApplication.shared.keyWindow?.rootViewController
        }
    ) {
        self.rootViewControllerProvider = rootViewControllerProvider
    }

    // MARK: - UIKitHierarchyInspectorType

    func topViewController() -> UIViewController? {
        guard let rootVC = rootViewControllerProvider() else {
            return nil
        }

        guard let highestPresentedVC = findHighestPresentedViewControllerInHierarchy(of: rootVC) else {
            return nil
        }

        return findTopViewControllerInHierarchy(of: highestPresentedVC)
    }

    // MARK: - Private

    private func findHighestPresentedViewControllerInHierarchy(of viewController: UIViewController) -> UIViewController? {
        if let presentedVC = viewController.presentedViewController {
            return findHighestPresentedViewControllerInHierarchy(of: presentedVC)
        }
        return viewController
    }

    private func findTopViewControllerInHierarchy(of viewController: UIViewController) -> UIViewController? {
        if let tabBarVC = viewController as? UITabBarController {
            guard let selectedVC = tabBarVC.selectedViewController else {
                return tabBarVC // when `UITabBarController` displays no view controllers
            }
            // When `UITabBarController` has selected VC, continue searching, as the selected VC
            // may be containing another hierarchy (e.g. `UINavigationController`).
            return findTopViewControllerInHierarchy(of: selectedVC)
        } else if let navigationVC = viewController as? UINavigationController {
            guard let topVC = navigationVC.topViewController else {
                return navigationVC // when `UINavigationController` displays no view controllers
            }
            // When `UINavigationController` has top VC, continue searching, as the top VC
            // may be containing another hierarchy (e.g. `UITabBarController`).
            return findTopViewControllerInHierarchy(of: topVC)
        } else {
            return viewController
        }
    }
}
