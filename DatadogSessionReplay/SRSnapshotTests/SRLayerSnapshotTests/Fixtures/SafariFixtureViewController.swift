/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SafariServices
import UIKit

internal final class SafariFixtureViewController: UIViewController, SFSafariViewControllerDelegate {
    private var initialLoadContinuation: CheckedContinuation<Void, Error>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    func showSafari() async throws {
        let safariViewController = SFSafariViewController(url: URL(string: "http://127.0.0.1")!)
        safariViewController.delegate = self

        try await withThrowingTaskGroup { group in
            group.addTask { @MainActor in
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { continuation in
                    self.initialLoadContinuation = continuation
                    self.present(safariViewController, animated: false)
                }
            }
            group.addTask {
                struct TimeoutError: Error {}
                try await Task.sleep(nanoseconds: 10_000_000_000)
                throw TimeoutError()
            }
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                let continuation = initialLoadContinuation
                initialLoadContinuation = nil
                continuation?.resume(throwing: error)
                group.cancelAll()
                throw error
            }
        }
    }

    func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
        // A failed load is expected for the local URL and still means Safari is ready.
        let continuation = initialLoadContinuation
        initialLoadContinuation = nil
        continuation?.resume()
    }
}
