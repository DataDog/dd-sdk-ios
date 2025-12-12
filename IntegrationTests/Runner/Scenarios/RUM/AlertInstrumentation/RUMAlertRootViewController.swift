/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogRUM

/// Handles the button taps from the main `RUMAlertScenario` storyboard screen, presenting several alerts and action sheets.
///
/// The equivalent to ``RUMAlertSwiftUI`` in UIKit.
class RUMAlertRootViewController: UIViewController {
    
    @IBAction func showSimpleAlert(_ sender: Any) {
        let alertController = UIAlertController(title: "This is an alert title.", message: "A message describing the problem.", preferredStyle: .alert)

        alertController.addAction(
            .init(title: "Cancel", style: .cancel)
        )

        alertController.addAction(
            .init(title: "OK", style: .default)
        )

        present(alertController, animated: false)
    }

    @IBAction func showManyButtonsAlert(_ sender: Any) {
        let alertController = UIAlertController(title: "This is an alert title.", message: "A message describing the problem.", preferredStyle: .alert)

        alertController.addAction(
            .init(title: "Cancel", style: .cancel)
        )

        alertController.addAction(
            .init(title: "OK", style: .default)
        )

        alertController.addAction(
            .init(title: "More Info", style: .default)
        )

        alertController.addAction(
            .init(title: "Delete", style: .destructive)
        )

        present(alertController, animated: false)
    }

    @IBAction func showAlertWithTextField(_ sender: Any) {
        let alertController = UIAlertController(title: "This is an alert title.", message: "Please type your name below.", preferredStyle: .alert)

        alertController.addAction(
            .init(title: "Cancel", style: .cancel)
        )

        alertController.addAction(
            .init(title: "OK", style: .default)
        )

        alertController.addTextField {
            $0.placeholder = "Name"
        }

        present(alertController, animated: false)
    }
    
    @IBAction func showSimpleActionSheet(_ sender: Any) {
        let alertController = UIAlertController(title: "This is an alert title.", message: "A message describing the problem.", preferredStyle: .actionSheet)

        alertController.addAction(
            .init(title: "Cancel", style: .cancel)
        )

        alertController.addAction(
            .init(title: "OK", style: .default)
        )

        present(alertController, animated: false)
    }
    
    @IBAction func showManyButtonsActionSheet(_ sender: Any) {
        let alertController = UIAlertController(title: "This is an alert title.", message: "A message describing the problem.", preferredStyle: .actionSheet)

        alertController.addAction(
            .init(title: "Cancel", style: .cancel)
        )

        alertController.addAction(
            .init(title: "OK", style: .default)
        )

        alertController.addAction(
            .init(title: "More Info", style: .default)
        )

        alertController.addAction(
            .init(title: "Delete", style: .destructive)
        )

        present(alertController, animated: false)
    }

}
