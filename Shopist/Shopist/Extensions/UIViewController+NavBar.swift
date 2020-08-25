/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

extension UIViewController {
    func addDefaultNavBarButtons() {
        let canGoBack = (navigationController?.viewControllers.count ?? 0) > 1
        if canGoBack {
            let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(goBack))
            backButton.accessibilityIdentifier = "back"
            navigationItem.leftBarButtonItem = backButton
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }

        let cartButton = UIBarButtonItem(image: UIImage(systemName: "cart"), style: .plain, target: self, action: #selector(goToCart))
        cartButton.accessibilityIdentifier = "cart"
        var buttonItems = navigationItem.rightBarButtonItems ?? []
        buttonItems.append(cartButton)
        navigationItem.rightBarButtonItems = buttonItems
    }

    @objc
    private func goBack() {
        rum?.registerUserAction(type: .tap, name: "Back")
        navigationController?.popViewController(animated: true)
    }

    @objc
    private func goToCart() {
        rum?.registerUserAction(type: .tap, name: "Go to cart")
        let cartVC = CheckoutViewController()
        let containerVC = UINavigationController(rootViewController: cartVC)
        present(containerVC, animated: true, completion: nil)
    }
}
