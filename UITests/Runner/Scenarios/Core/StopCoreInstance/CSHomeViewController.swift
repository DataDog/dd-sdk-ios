/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogTrace

internal class CSHomeViewController: UIViewController {
    @IBAction func didTapTestLogging(_ sender: UIButton) {
        sender.disableFor(seconds: 0.5)
        logger?.info("test message")
    }

    @IBAction func didTapTestTracing(_ sender: UIButton) {
        sender.disableFor(seconds: 0.5)
        let span = Tracer.shared().startSpan(operationName: "test span")
        span.finish(at: Date(timeIntervalSinceNow: 1))
    }
}
