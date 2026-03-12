/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogInternal
@testable import DatadogTrace

class RUMResourceActiveSpanAugmentationViewController: UIViewController {
    private var testScenario: URLSessionBaseScenario!
    private lazy var session = testScenario.getURLSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        testScenario = (appConfiguration.testScenario as! URLSessionBaseScenario)
    }

    @IBAction func sendRequestWithSampledSpan(_ sender: Any) {
        let span = Tracer.shared().startRootSpan(operationName: "some-active-span").setActive()
        sendRequest(with: span)
    }

    @IBAction func sendRequestWithNonSampledSpan(_ sender: Any) {
        guard let span = Tracer.shared().startRootSpan(operationName: "some-active-span", customSampleRate: 0).setActive() as? DDSpan else {
            return
        }
        sendRequest(with: span)
    }

    @IBAction func sendRequestWithManuallyKeptSpan(_ sender: Any) {
        let span = Tracer.shared().startRootSpan(operationName: "some-active-span").setActive()
        span.keepTrace()
        sendRequest(with: span)
    }

    @IBAction func sendRequestWithManuallyDroppedSpan(_ sender: Any) {
        let span = Tracer.shared().startRootSpan(operationName: "some-active-span").setActive()
        span.dropTrace()
        sendRequest(with: span)
    }

    private func sendRequest(with span: OTSpan) {
        let task = session.dataTask(with: testScenario.customPOSTRequest) { _, _, error in
            assert(error == nil)
            span.finish()
        }
        task.resume()
    }

}
