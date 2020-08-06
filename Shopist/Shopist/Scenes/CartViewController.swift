/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

private struct CellModel {
    enum Kind {
        case normal
        case bold
        case summary
    }
    let title: String
    let price: String
    let kind: Kind
}

final class CartViewController: UITableViewController {
    private var models = [CellModel]()
    private static let cellIdentifier = "cell"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cart"
        tableView.register(TableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.tableFooterView = UIView()
        tableView.allowsSelection = false

        let dismissButton = UIBarButtonItem(image: UIImage(systemName: "chevron.down"), style: .plain, target: self, action: #selector(dismissPage))
        navigationItem.leftBarButtonItem = dismissButton
        let payButton = UIBarButtonItem(image: UIImage(systemName: "creditcard"), style: .plain, target: self, action: #selector(pay))
        navigationItem.rightBarButtonItem = payButton
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupModels(from: cart)
    }

    func setupModels(from cart: Cart) {
        var newModels = cart.products.map { CellModel(title: $0.name, price: "€\($0.price)", kind: .normal) }
        newModels.append(CellModel(title: "Order Value", price: cart.orderValue.moneyString, kind: .bold))
        newModels.append(CellModel(title: "Tax", price: cart.tax.moneyString, kind: .bold))
        newModels.append(CellModel(title: "Shipping", price: cart.shipping.moneyString, kind: .bold))
        if let someDiscount = cart.discount {
            newModels.append(CellModel(title: "Discount", price: someDiscount.moneyString, kind: .bold))
        }
        newModels.append(CellModel(title: "Total", price: cart.total.moneyString, kind: .summary))
        models = newModels
    }

    @objc private func dismissPage() {
        presentingViewController?.dismiss(animated: true)
    }

    @objc private func pay() {
        print("Paid")
        cart.products.removeAll()
        dismissPage()
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        let model = models[indexPath.row]
        cell.textLabel?.text = model.title
        cell.detailTextLabel?.text = model.price
        switch model.kind {
        case .normal:
            cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        case .bold:
            cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        case .summary:
            cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return models.count
    }
}
