/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogTrace

internal class TSHomeViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        currentConsentValue = appConfiguration.testScenario!.initialTrackingConsent
    }

    var currentConsentValue: TrackingConsent? {
        didSet {
            switch currentConsentValue {
            case .granted: consentValueLabel.text = "GRANTED"
            case .notGranted: consentValueLabel.text = "NOT GRANTED"
            case .pending: consentValueLabel.text = "PENDING"
            default: fatalError()
            }

            // Because user info is attached to events in all features, we use it
            // to record current consent value for each event. This is later used
            // for assertions in integration tests.
            Datadog.setUserInfo(
                name: "John Doe",
                extraInfo: [
                    "current-consent-value": consentValueLabel.text!
                ]
            )
        }
    }

    @IBOutlet weak var consentValueLabel: UILabel!

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
