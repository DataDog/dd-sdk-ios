/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

/// Sends two requests to the same, cacheable URL: a "prime" request (populating the device's local HTTP cache)
/// followed by a "revalidate" request (which the OS may serve as a `304`-revalidated cache hit).
internal class RUMResourceCacheStatusViewController: UIViewController {
    private var testScenario: RUMResourceCacheStatusScenario!
    private lazy var session = testScenario.session

    override func viewDidLoad() {
        super.viewDidLoad()
        testScenario = (appConfiguration.testScenario as! RUMResourceCacheStatusScenario)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        sendPrimeRequest()
    }

    /// Sends the 1st ("prime") request, populating the device's local HTTP cache.
    private func sendPrimeRequest() {
        let task = session.dataTask(with: testScenario.cacheableResourceURL) { [weak self] _, _, error in
            assert(error == nil)
            self?.sendRevalidateRequest()
        }
        task.resume()
    }

    /// Sends the 2nd ("revalidate") request to the same URL, which the OS may serve from its local HTTP cache.
    private func sendRevalidateRequest() {
        let task = session.dataTask(with: testScenario.cacheableResourceURL) { _, _, error in
            assert(error == nil)
        }
        task.resume()
    }
}
