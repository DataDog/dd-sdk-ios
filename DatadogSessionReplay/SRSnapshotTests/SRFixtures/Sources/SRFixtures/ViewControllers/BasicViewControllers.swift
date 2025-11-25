/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SafariServices

internal class ShapesViewController: UIViewController {
    @IBOutlet weak var yellowView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        yellowView?.layer.borderWidth = 5
        yellowView?.layer.borderColor = UIColor.yellow.cgColor
    }
}

internal class TextsViewController: UIViewController {
    @IBOutlet weak var textView: UITextView?

    override func viewDidLoad() {
        super.viewDidLoad()
        textView?.becomeFirstResponder()
    }
}

public class PopupsViewController: UIViewController {
    @IBOutlet var buttons: [UIButton]!

    override public func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 15.0, *) {
            // Xcode 26 Interface Builder uses Background Configuration with corner radius that mismatch iOS 17.
            // Use fixed corner radius of 6 for backward compatibility
            buttons.forEach { button in
                button.configuration?.background.cornerRadius = 6
            }
        }
    }

    @IBAction public func showSafari() {
        present(SFSafariViewController(url: URL(string: "http://127.0.0.1")!), animated: false)
    }

    @IBAction public func showAlert() {
        let alertController = UIAlertController(
            title: "Alert Example",
            message: "This is an elaborate example of UIAlertController",
            preferredStyle: .alert
        )

        alertController.addTextField { textField in
            textField.placeholder = "Enter your name"
        }

        let confirmAction = UIAlertAction(title: "Confirm", style: .default) { [weak alertController] _ in
            if let textField = alertController?.textFields?[0], let text = textField.text {
                print("Name entered: \(text)")
            }
        }
        alertController.addAction(confirmAction)

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            print("Action cancelled")
        }
        alertController.addAction(cancelAction)

        let customAction = UIAlertAction(title: "Custom", style: .destructive) { _ in
            print("Custom action selected")
        }
        alertController.addAction(customAction)
        present(alertController, animated: false) {
            alertController.dismissKeyboard()
        }
    }

    @IBAction public func showActivity() {
        let activityViewController = UIActivityViewController(activityItems: [], applicationActivities: nil)
        present(activityViewController, animated: false, completion: nil)
    }
}
