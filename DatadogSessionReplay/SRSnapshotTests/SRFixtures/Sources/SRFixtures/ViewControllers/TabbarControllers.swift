/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

public class TabbarViewControllers: UIViewController {

    @IBOutlet var tabbars: [UITabBar]!
    
    public override func viewDidLoad() {
        for tabbar in tabbars {
            // Select the first tabbar's item
            // so we can see both a selected and unselected item
            tabbar.selectedItem = tabbar.items?[0]
        }
    }
}

public class EmbeddedTabbarController: UITabBarController {
    public override func viewDidLoad() {
        tabBar.unselectedItemTintColor = nil
    }
}

public class EmbeddedTabbarUnselectedTintColorController: UITabBarController {
    public override func viewDidLoad() {
        tabBar.unselectedItemTintColor = UIColor.green
    }
}
