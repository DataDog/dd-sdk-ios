/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

class TextFieldsViewController: UIViewController {
    @IBOutlet var textFields: [UITextField]!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Appears to be a bug in Xcode 26: Border style
        // from interface builder is not applied
        // https://stackoverflow.com/a/79796981
        textFields.forEach { textField in
            textField.borderStyle = .roundedRect
        }
    }
}
