/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal class ProductDetailViewController: UIViewController {
    @IBOutlet private weak var imageView: UIImageView!
    @IBOutlet private weak var descriptionLabel: UILabel!
    @IBOutlet private weak var priceLabel: UILabel!
    let product: Product

    init(product: Product) {
        self.product = product
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = product.name

        imageView.af.setImage(withURL: product.cover)
        descriptionLabel.text = product.name
        priceLabel.text = "€\(product.price)"

        setupBarButtons()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rum?.startView(viewController: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        rum?.stopView(viewController: self)
    }

    private func setupBarButtons() {
        let cartActionButton: UIBarButtonItem
        if cart.products.contains(product) {
            cartActionButton = UIBarButtonItem(image: UIImage(systemName: "cart.badge.minus"), style: .plain, target: self, action: #selector(removeFromCart))
        } else {
            cartActionButton = UIBarButtonItem(image: UIImage(systemName: "cart.badge.plus"), style: .plain, target: self, action: #selector(addToCart))
        }
        navigationItem.rightBarButtonItems = [cartActionButton]
        addGoToCartButton()
    }

    @objc
    private func addToCart() {
        cart.products.append(product)
        setupBarButtons()
    }

    @objc
    private func removeFromCart() {
        if let indexToRemove = cart.products.firstIndex(of: product) {
            cart.products.remove(at: indexToRemove)
        }
        setupBarButtons()
    }
}
