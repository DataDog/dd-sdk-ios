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
            //navbar.tintColor = .systemGreen
            print("navbar items:", navbar.items?.count ?? "nil")
            navbar.titleTextAttributes = [.foregroundColor: UIColor.blue]
            navbar.items?.forEach { item in
                item.leftBarButtonItem?.tintColor = .green
                item.rightBarButtonItem?.tintColor = .purple
            }
        }
    }

}
