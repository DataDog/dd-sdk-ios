/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal class SendRUMFixture2ViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        rumMonitor.startView(viewController: self)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            rumMonitor.addError(message: "Simulated view error", source: .source)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        rumMonitor.stopView(viewController: self)
    }
}
