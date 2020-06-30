/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog

internal class SendTracesFixtureViewController: UIViewController {
    private let backgroundQueue = DispatchQueue(label: "background-queue")

    /// Traces view appearing
    private var viewAppearingSpan: OTSpan!

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        viewAppearingSpan = tracer.startSpan(operationName: "view appearing")

        // Set `class: SendTracesFixtureViewController` baggage item on the root span, so it will be propagated to all child spans.
        viewAppearingSpan.setBaggageItem(key: "class", value: "\(type(of: self))")

        let dataDownloadingSpan = tracer.startSpan(
            operationName: "data downloading",
            childOf: viewAppearingSpan.context
        )
        dataDownloadingSpan.setTag(key: "data.kind", value: "image")
        dataDownloadingSpan.setTag(key: "data.url", value: URL(string: "https://example.com/image.png")!)
        dataDownloadingSpan.setTag(key: DDTags.resource, value: "GET /image.png")

        // Step #1: Manual tracing with complex hierarchy
        downloadSomeData { [weak self] data in
            // Simulate logging download progress
            dataDownloadingSpan.log(
                fields: [
                    OTLogFields.message: "download progress",
                    "progress": 0.99
                ]
            )

            dataDownloadingSpan.finish()
            guard let self = self else { return }

            let dataPresentationSpan = tracer.startSpan(
                operationName: "data presentation",
                childOf: self.viewAppearingSpan.context
            )
            self.present(data: data)
            dataPresentationSpan.setTag(key: OTTags.error, value: true)
            dataPresentationSpan.finish()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        viewAppearingSpan.finish()

        // Send requests which will be automatically traced as tracing auto-instrumentation is enabled
        let url = currentAppConfig().arbitraryNetworkURL
        let request = currentAppConfig().arbitraryNetworkRequest
        let dnsErrorURL = URL(string: "https://foo.bar")!
        // Step #2: Auto-instrumentated request with URL to succeed
        URLSession.shared.dataTask(with: url) { _, _, _ in
            // Step #3: Auto-instrumentated request with Request to fail
            URLSession.shared.dataTask(with: request) { _, _, _ in
                // Step #4: Auto-instrumentated request to return NSError
                URLSession.shared.dataTask(with: dnsErrorURL) { _, _, _ in }.resume()
            }.resume()
        }.resume()
    }

    /// Simulates doing an asynchronous work with completion.
    private func downloadSomeData(completion: @escaping (Data) -> Void) {
        backgroundQueue.async {
            Thread.sleep(forTimeInterval: 0.3)
            DispatchQueue.main.async { completion(Data()) }
        }
    }

    /// Simulates presenting some data.
    private func present(data: Data) {
        Thread.sleep(forTimeInterval: 0.06)
    }
}
