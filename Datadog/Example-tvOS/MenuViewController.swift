/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog_tvOS

class MenuViewController: UIViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        Global.rum.startView(viewController: self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        Global.rum.stopView(viewController: self)
    }

    @IBAction func didTapScreen1(_ sender: Any) {
        Global.rum.registerUserAction(type: .custom, name: "go to Screen 1")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let screen1ViewController = storyboard.instantiateViewController(identifier: "screen1")
            self.present(screen1ViewController, animated: true)
        }
    }

    @IBAction func didTapScreen2(_ sender: Any) {
        Global.rum.registerUserAction(type: .custom, name: "go to Screen 2")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let screen1ViewController = storyboard.instantiateViewController(identifier: "screen2")
            self.present(screen1ViewController, animated: true)
        }
    }
}
