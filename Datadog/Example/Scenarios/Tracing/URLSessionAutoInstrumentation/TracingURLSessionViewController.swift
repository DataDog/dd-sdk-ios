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

        callSuccessfullURL {
            self.callSuccessfullURLRequest {
                self.callBadURL {
                    // TODO: RUMM-731 Make calls to non-completion handler APIs
                }
            }
        }
    }

    private func callSuccessfullURL(completion: @escaping () -> Void) {
        let task = session.dataTask(with: testScenario.customGETResourceURL) { _, _, error in
            assert(error == nil)
            completion()
        }
        task.resume()
    }

    private func callSuccessfullURLRequest(completion: @escaping () -> Void) {
        let task = session.dataTask(with: testScenario.customPOSTRequest) { _, _, error in
            assert(error == nil)
            completion()
        }
        task.resume()
    }

    private func callBadURL(completion: @escaping () -> Void) {
        let task = session.dataTask(with: testScenario.badResourceURL) { _, _, error in
            assert(error != nil)
            completion()
        }
        task.resume()
    }
}
