/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogRUM
import DatadogCore
import DatadogInternal

class DebugRUMViewController: UIViewController {
    @IBOutlet weak var rumServiceNameTextField: UITextField!

    private var simulatedViewControllers: [UIViewController] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        rumServiceNameTextField.text = serviceName
        hideKeyboardWhenTapOutside()

        viewURLTextField.placeholder = viewURL
        actionViewURLTextField.placeholder = actionViewURL
        actionTypeTextField.placeholder = RUMActionType.default.toString
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

    private var actionType: RUMActionType {
        let actionType = actionTypeTextField.text.flatMap { RUMActionType(string: $0) }
        return actionType ?? RUMActionType.default
    }

    @IBAction func didTapSendActionEvent(_ sender: Any) {
        let viewController = createUIViewControllerSubclassInstance(named: actionViewURL)
        rumMonitor.startView(viewController: viewController)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            rumMonitor.addAction(type: self.actionType, name: (sender as! UIButton).currentTitle!)
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

    @IBOutlet weak var resourceTypeSegment: UISegmentedControl!
    @IBOutlet weak var resourceViewURLTextField: UITextField!
    @IBOutlet weak var resourceURLTextField: UITextField!
    @IBOutlet weak var sendResourceEventButton: UIButton!

    private var resourceViewURL: String {
        resourceViewURLTextField.text!.isEmpty ? "FooViewController" : resourceViewURLTextField.text!
    }

    private var resourceURL: String {
        resourceURLTextField.text!.isEmpty ? "https://api.shopist.io/checkout.json" : resourceURLTextField.text!
    }

    @IBAction func didTapSendResourceEvent(_ sender: Any) {
        let viewController = createUIViewControllerSubclassInstance(named: resourceViewURL)
        rumMonitor.startView(viewController: viewController)

        if resourceTypeSegment.selectedSegmentIndex == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.sendManualResource(completeAfter: 0.2)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.sendInstrumentedResource()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            rumMonitor.stopView(viewController: viewController)
        }
        simulatedViewControllers.append(viewController)
        sendResourceEventButton.disableFor(seconds: 0.5)
    }

    private func sendManualResource(completeAfter time: TimeInterval) {
        let request = URLRequest(url: URL(string: self.resourceURL)!)
        rumMonitor.startResource(
            resourceKey: "/resource/1",
            request: request
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + time) {
            rumMonitor.stopResource(
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

    private lazy var instrumentedSession: URLSession = {
        class InstrumentedDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {}
        URLSessionInstrumentation.enable(with: .init(delegateClass: InstrumentedDelegate.self))
        return URLSession(configuration: .ephemeral, delegate: InstrumentedDelegate(), delegateQueue: .main)
    }()

    private func sendInstrumentedResource() {
        var request = URLRequest(url: URL(string: self.resourceURL)!)
        request.httpMethod = "POST"
        instrumentedSession.dataTask(with: request) { _, _, error in
            if let error = error {
                print("🌍🔥 POST \(request.url!.absoluteString) completed with network error: \(error)")
            } else {
                print("🌍 POST \(request.url!.absoluteString) sent successfully")
            }
        }.resume()
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

    // MARK: - Telemetry Events

    @IBAction func didTapTelemetryEvent(_ sender: Any) {
        guard let button = sender as? UIButton, let title = button.currentTitle else {
            return
        }
        button.disableFor(seconds: 0.5)

        let telemetry = CoreRegistry.default.telemetry

        switch title {
        case "debug":
            telemetry.debug(
                id: UUID().uuidString,
                message: "DEBUG telemetry message",
                attributes: [
                    "attribute-foo": "foo",
                    "attribute-42": 42,
                ]
            )
        case "error":
            telemetry.error(
                id: UUID().uuidString,
                message: "ERROR telemetry message",
                kind: "error.telemetry.kind",
                stack: "error.telemetry.stack"
            )
        case "metric":
            telemetry.metric(
                name: "METRIC telemetry",
                attributes: [
                    "attribute-foo": "foo",
                    "attribute-42": 42,
                ],
                sampleRate: 100
            )
        case "usage":
            telemetry.send(
                telemetry: .usage(.setTrackingConsent(.granted))
            )
        default:
            break
        }
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

extension RUMActionType {
    init(string: String) {
        switch string {
        case "tap": self = .tap
        case "scroll": self = .scroll
        case "swipe": self = .swipe
        case "custom": self = .custom
        default: self = RUMActionType.default
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

    static var `default`: RUMActionType = .custom
}
