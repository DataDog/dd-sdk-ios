/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit
import Datadog

internal class TracingURLSessionViewController: UIViewController {
    private var testScenario: TracingURLSessionScenario!
    private lazy var session = URLSession(
        configuration: .default,
        delegate: DDURLSessionDelegate(),
        delegateQueue: nil
    )

    override func awakeFromNib() {
        super.awakeFromNib()
        self.testScenario = (appConfiguration.testScenario as! TracingURLSessionScenario)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        callSuccessfullFirstPartyURL {
            self.callSuccessfullFirstPartyURLRequest {
                self.callBadFirstPartyURL()
            }
        }

        callThirdPartyURL()
        callThirdPartyURLRequest()
    }

    private func callSuccessfullFirstPartyURL(completion: @escaping () -> Void) {
        // This request is instrumented. It sends the `Span`.
        let task = session.dataTask(with: testScenario.customGETResourceURL) { _, _, error in
            assert(error == nil)
            completion()
        }
        task.resume()
    }

    private func callSuccessfullFirstPartyURLRequest(completion: @escaping () -> Void) {
        // This request is instrumented. It sends the `Span`.
        let task = session.dataTask(with: testScenario.customPOSTRequest) { _, _, error in
            assert(error == nil)
            completion()
        }
        task.resume()
    }

    private func callBadFirstPartyURL() {
        // This request is instrumented. It sends the `Span`.
        let task = session.dataTask(with: testScenario.badResourceURL)
        task.resume()
    }

    private func callThirdPartyURL() {
        // This request is NOT instrumented. We test that it does not send the `Span`.
        let task = session.dataTask(with: testScenario.thirdPartyURL)
        task.resume()
    }

    private func callThirdPartyURLRequest() {
        // This request is NOT instrumented. We test that it does not send the `Span`.
        let task = session.dataTask(with: testScenario.thirdPartyRequest)
        task.resume()
    }
}
