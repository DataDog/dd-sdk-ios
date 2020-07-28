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

    private var simulatedViewControllers: [UIViewController] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        rumServiceNameTextField.text = appConfig.serviceName
        hideKeyboardWhenTapOutside()
        startDisplayingDebugInfo(in: consoleTextView)

        viewURLTextField.placeholder = viewURL
        actionViewURLTextField.placeholder = actionViewURL
        actionTypeTextField.placeholder = actionType
        resourceViewURLTextField.placeholder = resourceViewURL
        resourceURLTextField.placeholder = resourceURL
    }

    // MARK: - View Event

    @IBOutlet weak var viewURLTextField: UITextField!
    @IBOutlet weak var sendViewEventButton: UIButton!

    private var viewURL: String {
        viewURLTextField.text!.isEmpty ? "FooViewController" : viewURLTextField.text!
    }

    @IBAction func didTapSendViewEvent(_ sender: Any) {
        let viewController = createUIViewControllerSubclassInstance(named: viewURL)
        rumMonitor.startView(viewController: viewController)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            rumMonitor.stopView(viewController: viewController)
        }
        simulatedViewControllers.append(viewController)
        sendViewEventButton.disableFor(seconds: 0.5)
    }

    // MARK: - Action Event

    @IBOutlet weak var actionViewURLTextField: UITextField!
    @IBOutlet weak var actionTypeTextField: UITextField!
    @IBOutlet weak var sendActionEventButton: UIButton!

    private var actionViewURL: String {
        actionViewURLTextField.text!.isEmpty ? "FooViewController" : actionViewURLTextField.text!
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

    // MARK: - Resource Event

    @IBOutlet weak var resourceViewURLTextField: UITextField!
    @IBOutlet weak var resourceURLTextField: UITextField!
    @IBOutlet weak var sendResourceEventButton: UIButton!

    private var resourceViewURL: String {
        resourceViewURLTextField.text!.isEmpty ? "FooViewController" : resourceViewURLTextField.text!
    }

    private var resourceURL: String {
        resourceURLTextField.text!.isEmpty ? "/resource/1" : resourceURLTextField.text!
    }

    @IBAction func didTapSendResourceEvent(_ sender: Any) {
        let viewController = createUIViewControllerSubclassInstance(named: resourceViewURL)
        rumMonitor.startView(viewController: viewController)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let url = URL(string: "https://foo.com" + self.resourceURL)!
            rumMonitor.startResourceLoading(
                resourceName: "/resource/1",
                request: URLRequest(url: url)
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                rumMonitor.stopResourceLoading(
                    resourceName: "/resource/1",
                    response: HTTPURLResponse(
                        url: url,
                        mimeType: "image/jpeg",
                        expectedContentLength: -1,
                        textEncodingName: nil
                    )
                )
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            rumMonitor.stopView(viewController: viewController)
        }
        simulatedViewControllers.append(viewController)
        sendResourceEventButton.disableFor(seconds: 0.5)
    }
}

// MARK: - Private Helpers

/// Creates an instance of `UIViewController` subclass with a given name.
private func createUIViewControllerSubclassInstance(named viewControllerClassName: String) -> UIViewController {
    let theClass: AnyClass = objc_allocateClassPair(UIViewController.classForCoder(), viewControllerClassName, 0)!
    objc_registerClassPair(theClass)
    return theClass.alloc() as! UIViewController
}
