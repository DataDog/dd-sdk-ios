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

    override func viewDidLoad() {
        super.viewDidLoad()
        rumServiceNameTextField.text = appConfig.serviceName
        hideKeyboardWhenTapOutside()
        startDisplayingDebugInfo(in: consoleTextView)

        viewURLTextField.placeholder = viewURL
        actionViewURLTextField.placeholder = actionViewURL
        actionTypeTextField.placeholder = actionType
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

    // MARK: - Action Event

    @IBOutlet weak var actionViewURLTextField: UITextField!
    @IBOutlet weak var actionTypeTextField: UITextField!
    @IBOutlet weak var sendActionEventButton: UIButton!

    private var actionViewURL: String {
        actionViewURLTextField.text!.isEmpty ? "/hello/rum" : actionViewURLTextField.text!
    }

    private var actionType: String {
        let allowedTypes = ["custom", "click", "tap", "scroll", "swipe", "application_start"]
        let defaultType = "custom"
        let actionType = actionTypeTextField.text ?? defaultType
        return allowedTypes.contains(actionType) ? actionType : defaultType // limit to allowed types
    }

    @IBAction func didTapSendActionEvent(_ sender: Any) {
        rumMonitor.sendFakeActionEvent(viewURL: actionViewURL, actionType: actionType)
        sendActionEventButton.disableFor(seconds: 0.5)

        if actionType != actionTypeTextField.text { // if `actionType` was replaced with allowed type
            if !actionTypeTextField.text!.isEmpty { // when not using placeholder
                actionTypeTextField.text = actionType
            }
        }
    }
}
