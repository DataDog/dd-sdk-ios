/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SafariServices
import UIKit
import XCTest

internal final class SafariFixtureViewController: UIViewController, SFSafariViewControllerDelegate {
    private let initialLoad = XCTestExpectation(description: "Safari initial load")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    func showSafari() async {
        let safariViewController = SFSafariViewController(url: URL(string: "http://127.0.0.1")!)
        safariViewController.delegate = self

        let presentation = XCTestExpectation(description: "Safari presentation")
        present(safariViewController, animated: false) {
            presentation.fulfill()
        }

        let result = await XCTWaiter.fulfillment(of: [presentation, initialLoad], timeout: 10)
        XCTAssertEqual(result, .completed, "Safari did not finish presenting and loading within 10 seconds")
    }

    func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
        // A failed load is expected for the local URL and still means Safari is ready.
        initialLoad.fulfill()
    }
}
