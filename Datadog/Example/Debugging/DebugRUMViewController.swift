/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog

class DebugRUMViewController: UIViewController {
    @IBOutlet weak var rumServiceNameTextField: UITextField!
    @IBOutlet weak var consoleTextView: UITextView!

    private let rumMonitor = RUMMonitor.initialize(rumApplicationID: appConfig.rumApplicationID)

    override func viewDidLoad() {
        super.viewDidLoad()
        rumServiceNameTextField.text = appConfig.serviceName
        hideKeyboardWhenTapOutside()
        startDisplayingDebugInfo(in: consoleTextView)

        viewURLTextField.placeholder = viewURL
    }

    // MARK: - View Event

    @IBOutlet weak var viewURLTextField: UITextField!
    @IBOutlet weak var sendViewEventButton: UIButton!

    private var viewURL: String {
        viewURLTextField.text!.isEmpty ? "/hello/rum" : viewURLTextField.text!
    }

    @IBAction func didTapSendViewEvent(_ sender: Any) {
        rumMonitor.sendFakeViewEvent(viewURL: viewURL)
        sendViewEventButton.disableFor(seconds: 0.5)
    }
}
