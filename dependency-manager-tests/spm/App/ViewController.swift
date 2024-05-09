/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import UIKit
import DatadogRUM
import DatadogObjc
import DatadogSessionReplay // it should compile for iOS and tvOS, but APIs are only available on iOS

internal class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        DatadogSetup.initialize()

        // RUM APIs must be visible:
        RUM.enable(with: .init(applicationID: "app-id"))
        RUMMonitor.shared().startView(viewController: self)
        
        #if os(iOS)
        // Session Replay API must be visible:
        SessionReplay.enable(with: .init(replaySampleRate: 0))
        #endif

        addLabel()
    }

    private func addLabel() {
        let label = UILabel()
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)

        label.text = "Testing..."
        label.textColor = .white
        label.sizeToFit()
        label.center = view.center
    }
}
