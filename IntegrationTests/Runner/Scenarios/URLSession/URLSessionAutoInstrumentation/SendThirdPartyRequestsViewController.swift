/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogCore

internal class SendThirdPartyRequestsViewController: UIViewController {
    private var testScenario: URLSessionBaseScenario!
    private lazy var session = testScenario.getURLSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.testScenario = (appConfiguration.testScenario as! URLSessionBaseScenario)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        callThirdPartyURL()
        callThirdPartyURLRequest()

        // Only `RUMResourcesBaseScenario` (used by `RUMResourcesScenarioTests`) exercises OS-level HTTP
        // cache revalidation; other scenarios sharing this VC (e.g. Tracing) skip it.
        if let cacheScenario = testScenario as? RUMResourcesBaseScenario {
            sendCacheableResourcePrimeRequest(using: cacheScenario)
        }
    }

    private func callThirdPartyURL() {
        let task = session.dataTask(with: testScenario.thirdPartyURL)
        task.resume()
    }

    private func callThirdPartyURLRequest() {
        let task = session.dataTask(with: testScenario.thirdPartyRequest)
        task.resume()
    }

    /// Sends the 1st ("prime") request to `cacheableResourceURL`, populating the device's local HTTP cache.
    private func sendCacheableResourcePrimeRequest(using scenario: RUMResourcesBaseScenario) {
        let task = scenario.cacheEnabledSession.dataTask(with: scenario.cacheableResourceURL) { _, _, error in
            assert(error == nil)
            self.sendCacheableResourceRevalidateRequest(using: scenario)
        }
        task.resume()
    }

    /// Sends the 2nd ("revalidate") request to the same URL, which the OS may serve from its local HTTP cache.
    private func sendCacheableResourceRevalidateRequest(using scenario: RUMResourcesBaseScenario) {
        let task = scenario.cacheEnabledSession.dataTask(with: scenario.cacheableResourceURL) { _, _, error in
            assert(error == nil)
        }
        task.resume()
    }
}
