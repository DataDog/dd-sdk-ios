/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogTrace
import OpenTelemetryApi

class DebugOTelTracingViewController: UIViewController {
    @IBOutlet weak var serviceNameTextField: UITextField!
    @IBOutlet weak var isErrorSegmentedControl: UISegmentedControl!
    @IBOutlet weak var singleSpanOperationNameTextField: UITextField!
    @IBOutlet weak var singleSpanResourceNameTextField: UITextField!
    @IBOutlet weak var sendSingleSpanButton: UIButton!
    @IBOutlet weak var complexSpanOperationNameTextField: UITextField!
    @IBOutlet weak var sendComplexSpanButton: UIButton!
    @IBOutlet weak var sendSpanLinksButton: UIButton!
    @IBOutlet weak var consoleTextView: UITextView!

    private let queue1 = DispatchQueue(label: "com.datadoghq.debug-tracing1")
    private let queue2 = DispatchQueue(label: "com.datadoghq.debug-tracing2")
    private let queue3 = DispatchQueue(label: "com.datadoghq.debug-tracing3")

    override func viewDidLoad() {
        super.viewDidLoad()
        serviceNameTextField.text = serviceName
        hideKeyboardWhenTapOutside()
        startDisplayingDebugInfo(in: consoleTextView)
    }

    private var isError: Bool {
        isErrorSegmentedControl.selectedSegmentIndex == 1
    }

    // MARK: - Sending single span

    private var singleSpanOperationName: String {
        singleSpanOperationNameTextField.text!.isEmpty ? "otel single span" : singleSpanOperationNameTextField.text!
    }

    private var singleSpanResourceName: String? {
        singleSpanResourceNameTextField.text!.isEmpty ? nil : singleSpanResourceNameTextField.text!
    }

    @IBAction func didTapSendSingleSpan(_ sender: Any) {
        sendSingleSpanButton.disableFor(seconds: 0.5)

        let spanName = singleSpanOperationName
        let resourceName = singleSpanResourceName
        let isError = self.isError

        queue1.async {
            let span = otelTracer.spanBuilder(spanName: spanName)
                .startSpan()
            if let resourceName = resourceName {
                span.setAttribute(key: SpanTags.resource, value: resourceName)
            }
            if isError {
                // To only mark the span as an error, use the Open Tracing `error` tag:
                // span.setTag(key: "error", value: true)
                span.status = .error(description: "error description")
            }
            wait(seconds: 1)
            span.end()
        }
    }

    // MARK: - Sending complex span

    private var complexSpanOperationName: String {
        complexSpanOperationNameTextField.text!.isEmpty ? "otel complex span" : complexSpanOperationNameTextField.text!
    }

    @IBAction func didTapSendComplexSpan(_ sender: Any) {
        sendComplexSpanButton.disableFor(seconds: 0.5)

        let spanName = complexSpanOperationName

        queue1.async { [weak self] in
            guard let self = self else { return }

            let rootSpan = otelTracer
                .spanBuilder(spanName: spanName)
                .setActive(true)
                .startSpan()
            wait(seconds: 0.5)

            self.queue2.sync {
                let child1 = otelTracer.spanBuilder(spanName: "otel child operation 1")
                    .startSpan()
                wait(seconds: 0.5)
                child1.end()

                wait(seconds: 0.1)

                let child2 = otelTracer
                    .spanBuilder(spanName: "otel child operation 2")
                    .setParent(rootSpan)
                    .startSpan()
                wait(seconds: 0.5)

                self.queue3.sync {
                    let grandChild = otelTracer
                        .spanBuilder(spanName: "otel grandchild operation")
                        .setParent(child2)
                        .startSpan()
                    wait(seconds: 1)
                    grandChild.end()
                }

                OpenTelemetry.instance.contextProvider.setActiveSpan(child2)
                let child2Child = otelTracer.spanBuilder(spanName: "otel child2 child")
                    .startSpan()
                wait(seconds: 0.5)
                child2Child.end()

                child2.end()
            }

            wait(seconds: 0.5)
            rootSpan.end()
        }
    }

    // MARK: - Sending span links

    @IBAction func didTabSendSpanLinks(_ sender: Any) {
        sendSpanLinksButton.disableFor(seconds: 1)
        queue1.async {
            let span1 = otelTracer.spanBuilder(spanName: "span 1")
                .startSpan()
            wait(seconds: 0.5)
            
            let span2 = otelTracer.spanBuilder(spanName: "span 2")
                .addLink(spanContext: span1.context)
                .startSpan()
            wait(seconds: 0.5)
            span2.end()
        
            span1.end()
        }
    }
}

private func wait(seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}
