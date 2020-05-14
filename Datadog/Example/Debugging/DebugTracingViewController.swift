/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import OpenTracing

class DebugTracingViewController: UIViewController {
    @IBOutlet weak var serviceNameTextField: UITextField!
    @IBOutlet weak var isErrorSegmentedControl: UISegmentedControl! // TODO: RUMM-401 Set `isError` on span
    @IBOutlet weak var singleSpanOperationNameTextField: UITextField!
    @IBOutlet weak var sendSingleSpanButton: UIButton!
    @IBOutlet weak var complexSpanOperationNameTextField: UITextField!
    @IBOutlet weak var sendComplexSpanButton: UIButton!
    @IBOutlet weak var consoleTextView: UITextView!

    private let queue1 = DispatchQueue(label: "com.datadoghq.debug-tracing1")
    private let queue2 = DispatchQueue(label: "com.datadoghq.debug-tracing2")
    private let queue3 = DispatchQueue(label: "com.datadoghq.debug-tracing3")

    override func viewDidLoad() {
        super.viewDidLoad()
        serviceNameTextField.text = appConfig.serviceName
        hideKeyboardWhenTapOutside()
        startDisplayingDebugInfo(in: consoleTextView)
    }

    // MARK: - Sending single span

    private var singleSpanOperationName: String {
        singleSpanOperationNameTextField.text!.isEmpty ? "single span" : singleSpanOperationNameTextField.text!
    }

    @IBAction func didTapSendSingleSpan(_ sender: Any) {
        sendSingleSpanButton.disableFor(seconds: 0.5)

        let spanName = singleSpanOperationName

        queue1.async {
            let span = Global.sharedTracer.startSpan(operationName: spanName)
            wait(seconds: 1)
            span.finish()
        }
    }

    // MARK: - Sending complex span

    private var complexSpanOperationName: String {
        complexSpanOperationNameTextField.text!.isEmpty ? "complex span" : complexSpanOperationNameTextField.text!
    }

    @IBAction func didTapSendComplexSpan(_ sender: Any) {
        sendComplexSpanButton.disableFor(seconds: 0.5)

        let spanName = complexSpanOperationName

        queue1.async { [weak self] in
            guard let self = self else { return }

            let rootSpan = Global.sharedTracer.startSpan(operationName: spanName)
            wait(seconds: 0.5)

            self.queue2.sync {
                let child1 = Global.sharedTracer.startSpan(operationName: "child operation 1", childOf: rootSpan.context)
                wait(seconds: 0.5)
                child1.finish()

                wait(seconds: 0.1)

                let child2 = Global.sharedTracer.startSpan(operationName: "child operation 2", childOf: rootSpan.context)
                wait(seconds: 0.5)

                self.queue3.sync {
                    let grandChild = Global.sharedTracer.startSpan(operationName: "grandchild operation", childOf: child2.context)
                    wait(seconds: 1)
                    grandChild.finish()
                }

                child2.finish()
            }

            wait(seconds: 0.5)
            rootSpan.finish()
        }
    }
}

private func wait(seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: 0.5)
}
