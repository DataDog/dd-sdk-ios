/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

extension UIViewController {
    func addGoToCartButton() {
        let cartButton = UIBarButtonItem(image: UIImage(systemName: "cart"), style: .plain, target: self, action: #selector(goToCart))
        var buttonItems = navigationItem.rightBarButtonItems ?? []
        buttonItems.append(cartButton)
        navigationItem.rightBarButtonItems = buttonItems
    }

    @objc
    private func goToCart() {
        let cartVC = CartViewController()
        let containerVC = UINavigationController(rootViewController: cartVC)
        present(containerVC, animated: true, completion: nil)
    }
}
