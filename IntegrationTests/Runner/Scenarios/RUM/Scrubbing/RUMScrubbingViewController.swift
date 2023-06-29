/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore

internal class RUMScrubbingViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        simulateRUMView()
    }

    private func simulateRUMView() {
        rumMonitor.startView(viewController: self, name: "ViewName (sensitive detail)")

        simulateRUMUserAction()
        simulateRUMError()
        simulateRUMResources {
            rumMonitor.stopView(viewController: self)
        }
    }

    private func simulateRUMUserAction() {
        rumMonitor.addAction(type: .tap, name: "Purchase (sensitive detail)")
    }

    private func simulateRUMError() {
        rumMonitor.addError(message: "Error message (sensitive detail).", source: .source)
    }

    private func simulateRUMResources(completion: @escaping () -> Void) {
        let simulatedResourceKey1 = "/resource/1"
        let simulatedResourceRequest1 = URLRequest(url: URL(string: "https://foo.com/resource/1?q=sensitive-detail")!)
        let simulatedResourceKey2 = "/resource/2"
        let simulatedResourceRequest2 = URLRequest(url: URL(string: "https://foo.com/resource/2?q=sensitive-detail")!)
        let simulatedResourceLoadingTime: TimeInterval = 0.1

        rumMonitor.startResource(
            resourceKey: simulatedResourceKey1,
            request: simulatedResourceRequest1
        )

        rumMonitor.startResource(
            resourceKey: simulatedResourceKey2,
            request: simulatedResourceRequest2
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + simulatedResourceLoadingTime) {
            rumMonitor.stopResource(
                resourceKey: simulatedResourceKey1,
                response: HTTPURLResponse(
                    url: simulatedResourceRequest1.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"]
                )!
            )

            rumMonitor.stopResourceWithError(
                resourceKey: simulatedResourceKey2,
                error: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorBadServerResponse,
                    userInfo: [NSLocalizedDescriptionKey: "Bad response (sensitive detail)."]
                ),
                response: HTTPURLResponse(
                    url: simulatedResourceRequest2.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )

            completion()
        }
    }
}
