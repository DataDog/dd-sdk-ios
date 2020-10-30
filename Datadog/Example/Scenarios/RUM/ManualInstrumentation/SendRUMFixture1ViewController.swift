/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
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

        rumMonitor.startView(viewController: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        rumMonitor.stopView(viewController: self)
    }

    @IBAction func didTapDownloadResourceButton(_ sender: Any) {
        let simulatedresourceKey1 = "/resource/1"
        let simulatedResourceURL1 = URL(string: "https://foo.com/resource/1")!
        let simulatedresourceKey2 = "/resource/2"
        let simulatedResourceURL2 = URL(string: "https://foo.com/resource/2")!
        let simulatedResourceLoadingTime: TimeInterval = 0.1

        rumMonitor.addUserAction(
            type: .tap,
            name: (sender as! UIButton).currentTitle!,
            attributes: ["button.description": String(describing: sender)]
        )

        rumMonitor.startResourceLoading(
            resourceKey: simulatedresourceKey1,
            url: simulatedResourceURL1,
            httpMethod: .GET
        )

        rumMonitor.startResourceLoading(
            resourceKey: simulatedresourceKey2,
            url: simulatedResourceURL2,
            httpMethod: .GET
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + simulatedResourceLoadingTime) {
            rumMonitor.stopResourceLoading(
                resourceKey: simulatedresourceKey1,
                kind: .image,
                httpStatusCode: 200
            )

            rumMonitor.stopResourceLoadingWithError(
                resourceKey: simulatedresourceKey2,
                error: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorBadServerResponse,
                    userInfo: [NSLocalizedDescriptionKey: "Bad response."]
                ),
                httpStatusCode: 400
            )

            // Reveal the "Push Next Screen" button so UITest can continue
            self.pushNextScreenButton.isHidden = false
        }
    }
}
