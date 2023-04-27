/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class ShapesViewController: UIViewController {
    @IBOutlet weak var yellowView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        yellowView?.layer.borderWidth = 5
        yellowView?.layer.borderColor = UIColor.yellow.cgColor
    }
}

internal class PopupsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(showAlert))
        view.addGestureRecognizer(tap)
    }

    @objc func showAlert() {
        let alert = UIAlertController(title: "Test", message: "Test", preferredStyle: .alert)
        alert.addAction(.init(title: "Accept", style: .destructive))
        present(alert, animated: false)
    }
}
