/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import Datadog

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
    }

    private func callThirdPartyURL() {
        if #available(iOS 13.0, *) {
            Task {
                let data = try await session.data(from: testScenario.thirdPartyURL)
                print(data)
            }
        } else {
            // Fallback on earlier versions
        }
    }

    private func callThirdPartyURLRequest() {
        if #available(iOS 13.0, *) {
            Task {
                let data = try await session.data(for: testScenario.thirdPartyRequest)
                print(data)
            }
        } else {
            // Fallback on earlier versions
        }
    }
}
