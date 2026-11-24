/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

@available(iOS 26.0, *)
final class TabAccessoryFixtureViewController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let tabs = [
            ("Podcasts", "square.grid.3x3.fill"),
            ("Playlists", "list.bullet"),
            ("Discover", "magnifyingglass"),
            ("Up Next", "text.line.first.and.arrowtriangle.forward"),
            ("Profile", "person")
        ]
        viewControllers = tabs.enumerated().map { index, tab in
            let viewController = UIViewController()
            viewController.view.backgroundColor = .systemBackground
            viewController.tabBarItem = UITabBarItem(
                title: tab.0,
                image: UIImage(systemName: tab.1),
                tag: index
            )
            return viewController
        }
        selectedIndex = 2

        let content = UIView()
        let label = UILabel()
        label.text = "Now Playing"
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 52),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        bottomAccessory = UITabAccessory(contentView: content)
    }
}
