/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal class CrashReportingViewController: UIViewController {
    @IBOutlet weak var sendingCrashReportLabel: UILabel!
    @IBOutlet weak var crashTheAppButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        let testScenario = (appConfiguration.testScenario as! CrashReportingCollectOrSendScenario)

        if testScenario.hadPendingCrashReportDataOnStartup {
            sendingCrashReportLabel.isHidden = false
            crashTheAppButton.isHidden = true
        } else {
            sendingCrashReportLabel.isHidden = true
            crashTheAppButton.isHidden = false
        }
    }

    @IBAction func didTapCrashTheApp(_ sender: Any) {
        fatalError("The 'Crash The App' button was tapped.")
    }
}
