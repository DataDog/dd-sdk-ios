/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

public final class NavigationBarControllers: UIViewController {

    @IBOutlet var navigationBars: [UINavigationBar]!

    public func setTintColor() {
        for navbar in navigationBars {
            navbar.titleTextAttributes = [.foregroundColor: UIColor.cyan]
            navbar.items?.forEach { item in
                if let leftItems = item.leftBarButtonItems {
                    for leftItem in leftItems {
                        leftItem.tintColor = .green
                    }
                }
                if let rightItems = item.rightBarButtonItems {
                    for rightItem in rightItems {
                        rightItem.tintColor = .purple
                    }
                }
            }
        }
    }

}

/// This class allows us to push a view controller onto the navigation stack during snapshot tests.
public final class TestNavigationController: UINavigationController {
    public func pushNextView() {
        let firstVC = self.viewControllers.first
        firstVC?.performSegue(withIdentifier: "showNext", sender: self)
    }
}
