/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogRUM

internal class SendRUMFixture3ViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        rumMonitor.startView(key: "fixture3-vc", name: "SendRUMFixture3View")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            rumMonitor.addError(
                message: "Simulated view error with fingerprint",
                source: .source, attributes: [
                    RUM.Attributes.errorFingerprint: "fake-fingerprint"
                ]
            )
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        rumMonitor.stopView(key: "fixture3-vc")
    }
}
