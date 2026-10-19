/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SafariServices
import UIKit

internal final class SafariFixtureViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    func showSafari() {
        let safariViewController = SFSafariViewController(url: URL(string: "http://127.0.0.1")!)
        present(safariViewController, animated: false)
    }
}
