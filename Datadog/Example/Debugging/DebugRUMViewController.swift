/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Datadog

class DebugRUMViewController: UIViewController {
    @IBOutlet weak var rumServiceNameTextField: UITextField!
    @IBOutlet weak var consoleTextView: UITextView!

    private var simulatedViewControllers: [UIViewController] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        rumServiceNameTextField.text = (appConfiguration as? ExampleAppConfiguration)?.serviceName
        hideKeyboardWhenTapOutside()
        startDisplayingDebugInfo(in: consoleTextView)

        viewURLTextField.placeholder = viewURL
        actionViewURLTextField.placeholder = actionViewURL
        actionTypeTextField.placeholder = RUMUserActionType.default.toString
        resourceViewURLTextField.placeholder = resourceViewURL
        resourceURLTextField.placeholder = resourceURL
        errorViewURLTextField.placeholder = errorViewURL
        errorMessageTextField.placeholder = errorMessage
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

    private var actionType: RUMUserActionType {
        let actionType = actionTypeTextField.text.flatMap { RUMUserActionType(string: $0) }
        return actionType ?? RUMUserActionType.default
    }

    @IBAction func didTapSendActionEvent(_ sender: Any) {
        let viewController = createUIViewControllerSubclassInstance(named: actionViewURL)
        rumMonitor.startView(viewController: viewController)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            rumMonitor.addUserAction(type: self.actionType, name: (sender as! UIButton).currentTitle!)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            rumMonitor.stopView(viewController: viewController)
        }
        simulatedViewControllers.append(viewController)
        sendActionEventButton.disableFor(seconds: 0.5)

        if actionType.toString != actionTypeTextField.text { // if `actionType` was replaced with allowed type
            if !actionTypeTextField.text!.isEmpty { // when not using placeholder
                actionTypeTextField.text = actionType.toString
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
            let request = URLRequest(url: URL(string: "https://foo.com" + self.resourceURL)!)
            rumMonitor.startResourceLoading(
                resourceKey: "/resource/1",
                request: request
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                rumMonitor.stopResourceLoading(
                    resourceKey: "/resource/1",
                    response: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "image/png"]
                    )!
                )
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            rumMonitor.stopView(viewController: viewController)
        }
        simulatedViewControllers.append(viewController)
        sendResourceEventButton.disableFor(seconds: 0.5)
    }

    // MARK: - Error Event

    @IBOutlet weak var errorViewURLTextField: UITextField!
    @IBOutlet weak var errorMessageTextField: UITextField!
    @IBOutlet weak var sendErrorEventButton: UIButton!

    private var errorViewURL: String {
        errorViewURLTextField.text!.isEmpty ? "FooViewController" : errorViewURLTextField.text!
    }

    private var errorMessage: String {
        errorMessageTextField.text!.isEmpty ? "Error message" : errorMessageTextField.text!
    }

    @IBAction func didTapSendErrorEvent(_ sender: Any) {
        let viewController = createUIViewControllerSubclassInstance(named: errorViewURL)
        rumMonitor.startView(viewController: viewController)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            rumMonitor.addError(message: self.errorMessage, source: .source)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            rumMonitor.stopView(viewController: viewController)
        }
        simulatedViewControllers.append(viewController)
        sendErrorEventButton.disableFor(seconds: 0.5)
    }
}

// MARK: - Private Helpers

/// Creates an instance of `UIViewController` subclass with a given name.
private func createUIViewControllerSubclassInstance(named viewControllerClassName: String) -> UIViewController {
    let theClass: AnyClass = NSClassFromString(viewControllerClassName) ?? {
        let cls: AnyClass
        cls = objc_allocateClassPair(UIViewController.classForCoder(), viewControllerClassName, 0)!
        objc_registerClassPair(cls)
        return cls
    }()
    return theClass.alloc() as! UIViewController
}

extension RUMUserActionType {
    init(string: String) {
        switch string {
        case "tap": self = .tap
        case "scroll": self = .scroll
        case "swipe": self = .swipe
        case "custom": self = .custom
        default: self = RUMUserActionType.default
        }
    }

    var toString: String {
        switch self {
        case .tap: return "tap"
        case .click: return "click"
        case .scroll: return "scroll"
        case .swipe: return "swipe"
        case .custom: return "custom"
        }
    }

    static var `default`: RUMUserActionType = .custom
}
