/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class SendRUMFixture1ViewController: UIViewController {
    @IBOutlet weak var pushNextScreenButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Hide the "Push Next Screen" button until simulated resource is loaded
        pushNextScreenButton.isHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        rumMonitor.startView(viewController: self, name: "SendRUMFixture1View")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            rumMonitor.addTiming(name: "content-ready")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        rumMonitor.stopView(viewController: self)
    }

    @IBAction func didTapDownloadResourceButton(_ sender: Any) {
        rumMonitor.addTiming(name: "first-interaction")

        let simulatedResourceKey1 = "/resource/1"
        let simulatedResourceRequest1 = URLRequest(url: URL(string: "https://foo.com/resource/1")!)
        let simulatedResourceKey2 = "/resource/2"
        let simulatedResourceRequest2 = URLRequest(url: URL(string: "https://foo.com/resource/2")!)
        let simulatedResourceLoadingTime: TimeInterval = 0.1

        rumMonitor.addAction(
            type: .tap,
            name: (sender as! UIButton).currentTitle!,
            attributes: ["button.description": String(describing: sender)]
        )

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
                    userInfo: [NSLocalizedDescriptionKey: "Bad response."]
                ),
                response: HTTPURLResponse(
                    url: simulatedResourceRequest2.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )

            // Reveal the "Push Next Screen" button so UITest can continue
            self.pushNextScreenButton.isHidden = false
        }
    }
}
