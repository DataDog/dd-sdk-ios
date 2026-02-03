/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogRUM

final class RUMFeatureOperationsNextViewController: UIViewController {

    @IBAction func didTapSucceedLoginFlowButton(_ sender: Any) {
        rumMonitor.succeedFeatureOperation(
            name: Operation.login()
        )
    }
}
