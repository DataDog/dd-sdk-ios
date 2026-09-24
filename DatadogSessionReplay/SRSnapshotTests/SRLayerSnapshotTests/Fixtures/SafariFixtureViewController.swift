/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SafariServices
import UIKit

internal final class SafariFixtureViewController: UIViewController, SFSafariViewControllerDelegate {
    private var completion: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    func showSafari(completion: @escaping () -> Void) {
        self.completion = completion

        let safariViewController = SFSafariViewController(url: URL(string: "http://127.0.0.1")!)
        safariViewController.delegate = self
        present(safariViewController, animated: false)
    }

    func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
        // A failed load is expected for the local URL and still means Safari is ready.
        let completion = self.completion
        self.completion = nil
        completion?()
    }
}
