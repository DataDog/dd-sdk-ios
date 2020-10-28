/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog

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

internal final class CheckoutViewController: UITableViewController {
    private static var randomError: NSError? {
        if UInt8.random(in: 1...40) == 1 {
            return NSError(
                domain: "GraphQL",
                code: 11_235,
                userInfo: [NSLocalizedDescriptionKey: "Something happened..."]
            )
        }
        return nil
    }
    private let discountField: UITextField = {
        let title = UILabel(frame: .zero)
        title.text = "Discount Code "
        let field = UITextField(frame: .zero)
        field.placeholder = "12345"
        field.leftView = title
        field.leftViewMode = .always
        return field
    }()
    private var models = [CellModel]() {
        didSet {
            self.tableView.reloadData()
        }
    }
    private static let cellIdentifier = "cell"
    private var hasOngoingComputation = false
    private var viewDidAppearDate: Date?
    private var totalAmount: Float = 0.0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cart"
        tableView.register(TableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.allowsSelection = false
        tableView.tableFooterView = {
            let footerView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 60))
            footerView.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
            discountField.cover(footerView)
            return footerView
        }()

        let dismissButton = UIBarButtonItem(image: UIImage(systemName: "chevron.down"), style: .plain, target: self, action: #selector(dismissPage))
        navigationItem.leftBarButtonItem = dismissButton
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearDate = Date()

        if !hasOngoingComputation {
            hasOngoingComputation = true
            cart.generateBreakdown {
                logger.info("Cart is shown with \($0.products.count) items")
                self.hasOngoingComputation = false
                self.setupModels(from: $0)
            }
        }

        api.fakeUpdateInfoCall()
        api.fakeFetchFontCall()
    }

    func setupModels(from cartBreakdown: Cart.Breakdown) {
        api.fakeFetchShippingAndTax()
        var newModels = cartBreakdown.products.map { CellModel(title: $0.name, price: "€\($0.price)", kind: .normal) }
        newModels.append(CellModel(title: "Order Value", price: cartBreakdown.orderValue.moneyString, kind: .bold))
        newModels.append(CellModel(title: "Tax", price: cartBreakdown.tax.moneyString, kind: .bold))
        newModels.append(CellModel(title: "Shipping", price: cartBreakdown.shipping.moneyString, kind: .bold))
        if let someDiscount = cartBreakdown.discount {
            newModels.append(CellModel(title: "Discount", price: someDiscount.moneyString, kind: .bold))
        }
        newModels.append(CellModel(title: "Total", price: cartBreakdown.total.moneyString, kind: .summary))
        models = newModels

        if cartBreakdown.products.isEmpty {
            Global.rum.addError(message: "Cart is empty -> Pay button is hidden", source: .source)
        } else {
            addPayButton()
        }

        totalAmount = cartBreakdown.total
    }

    private func addPayButton() {
        let payButton = UIBarButtonItem(image: UIImage(systemName: "creditcard"), style: .plain, target: self, action: #selector(pay))
        payButton.accessibilityIdentifier = "pay"
        navigationItem.rightBarButtonItem = payButton
    }

    @objc
    private func dismissPage() {
        presentingViewController?.dismiss(animated: true)
    }

    @objc
    private func pay() {
        Global.rum.addAttribute(forKey: "hasPurchased", value: true)
        if let someDate = viewDidAppearDate {
            let timeToTapPayButton = Date().timeIntervalSince(someDate)
            logger.info(String(format: "Pay is tapped in %.2f seconds", timeToTapPayButton))
        }
        if let randomError = Self.randomError {
            self.handleError(randomError)
            return
        }
        api.checkout(with: discountField.text) { result in
            switch result {
            case .success:
                self.handleSuccess()
            case .failure(let error):
                self.handleError(error)
            }
        }
    }

    private func handleSuccess() {
        Global.rum.addUserAction(type: .custom, name: "Purchase", attributes: ["purchaseAmount": totalAmount])
        let alert = UIAlertController(title: "Success", message: nil, preferredStyle: .alert)
        let action = UIAlertAction(title: "OK", style: .default) { action in
            cart.products.removeAll()
            self.goToHomepage()
        }
        alert.addAction(action)
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }

    private func handleError(_ error: Error) {
        Global.rum.addUserAction(type: .custom, name: "Purchase failed")
        let nsError = error as NSError
        let title = "Error"
        let message = nsError.localizedDescription
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true, completion: nil)
        }
    }

    private func goToHomepage() {
        let navController = self.presentingViewController as? UINavigationController
        navController?.popToRootViewController(animated: false)
        self.dismissPage()
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
