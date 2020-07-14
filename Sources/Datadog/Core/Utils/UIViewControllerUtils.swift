/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

internal struct UIViewControllerUtils {
    static func getRootViewController(for view: UIView) -> UIViewController? {
        guard let rootViewController = view.window?.rootViewController else {
            return nil
        }
        return UIViewControllerUtils.topViewController(for: rootViewController)
    }

    static func topViewController(for rootViewController: UIViewController) -> UIViewController? {
        if let nextRootViewController = UIViewControllerUtils.nextRootViewController(for: rootViewController ) {
            return UIViewControllerUtils.topViewController(for: nextRootViewController)
        }
        return rootViewController
    }

    static func nextRootViewController(for viewController: UIViewController) -> UIViewController? {
        if let presentedViewController = viewController.presentedViewController {
            return presentedViewController
        }

        if let navigationController = viewController as? UINavigationController {
            return navigationController.viewControllers.last
        }

        if let tabBarController = viewController as? UITabBarController {
            return tabBarController.selectedViewController
        }

        if let children = viewController.children.first {
            return children
        }
        return nil
    }

    static func getInstrumentedName( for viewController: UIViewController) -> String {
        var name = (type(of: viewController).description())

        if let title = viewController.title {
            name += ", title: \(title)"
        } else if let parent = viewController.parent {
            if let navigationController = parent as? UINavigationController,
                let navigationTitle = navigationController.navigationBar.topItem?.title {
                name += ", title: \(navigationTitle)"
            } else if let tabBarController = parent as? UITabBarController,
                let tabTitle = tabBarController.tabBarItem.title {
                name += ", title: \(tabTitle)"
            }
        }
        return name
    }
}
