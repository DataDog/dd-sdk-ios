/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogCore

internal class SendFirstPartyRequestsViewController: UIViewController {
    private var testScenario: URLSessionBaseScenario!
    private lazy var session = testScenario.getURLSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        testScenario = (appConfiguration.testScenario as! URLSessionBaseScenario)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        callSuccessfullFirstPartyURL()
        callSuccessfullFirstPartyURLRequest()
        callBadFirstPartyURL()
    }

    private func callSuccessfullFirstPartyURL() {
        let task = session.dataTask(with: testScenario.customGETResourceURL) { _, _, error in
            assert(error == nil)
        }
        task.resume()
    }

    private func callSuccessfullFirstPartyURLRequest() {
        let task = session.dataTask(with: testScenario.customPOSTRequest) { _, _, error in
            assert(error == nil)
        }
        task.resume()
    }

    private func callBadFirstPartyURL() {
        let task = session.dataTask(with: testScenario.badResourceURL)
        task.resume()
    }
}
