/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogRUM

class DebugCrashReportingWithRUMViewController: UIViewController {
    @IBOutlet weak var rumServiceNameTextField: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        rumServiceNameTextField.text = serviceName
        viewNameTextField.placeholder = viewName
    }

    private func crash() {
        let objc = CrashReportingObjcHelpers()
        objc.throwUncaughtNSException()
    }

    // MARK: - Crash after starting RUM session

    @IBOutlet weak var viewNameTextField: UITextField!

    private var viewName: String {
        viewNameTextField.text!.isEmpty ? "FooViewController" : viewNameTextField.text!
    }

    @IBAction func didTapCrashAfterStartingRUMSession(_ sender: Any) {
        (sender as? UIButton)?.disableFor(seconds: 0.5)

        rumMonitor.startView(key: viewName, name: viewName, attributes: [:])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.crash()
        }
    }

    // MARK: - Crash before starting RUM session

    @IBAction func didTapCrashBeforeStartingRUMSession(_ sender: Any) {
        (sender as? UIButton)?.disableFor(seconds: 0.5)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.crash()
        }
    }
}
