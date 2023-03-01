/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Datadog

final class RUMMobileVitalsViewController: UIViewController {

    @IBAction func noOpButtonTapped(_ sender: Any) {
        print("No-op button tapped... Sending view update...")
    }

    @IBAction func blockMainThreadButtonTapped(_ sender: Any) {
        print("❌ Blocking main thread at \(Date())...")
        let startDate = Date()
        var i = 1
        while true {
            i += 1
            if Date().timeIntervalSince(startDate) > 3.0 {
                print("✅ Main thread is unblocked!")
                break
            }
        }
    }

    @IBAction func startNewViewButtonTapped(_ sender: Any){
        print("Start New View button tapped... Starting new view...")

        Global.rum.startView(key: "sample view")
        Global.rum.stopView(key: "sample view")
    }

}
