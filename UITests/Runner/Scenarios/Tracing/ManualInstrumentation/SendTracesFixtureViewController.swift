/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
import DatadogTrace

internal class SendTracesFixtureViewController: UIViewController {
    private let backgroundQueue = DispatchQueue(label: "background-queue")

    override func viewDidLoad() {
        super.viewDidLoad()

        let tracer = Tracer.shared()

        let viewLoadingSpan = tracer
            .startRootSpan(operationName: "view loading")
            .setActive()

        // Set `class: SendTracesFixtureViewController` baggage item on the active span, so it will be propagated to all child spans.
        viewLoadingSpan.setBaggageItem(key: "class", value: "\(type(of: self))")

        let dataDownloadingSpan = tracer.startSpan(operationName: "data downloading")
        dataDownloadingSpan.setTag(key: "data.kind", value: "image")
        dataDownloadingSpan.setTag(key: "data.url", value: URL(string: "https://example.com/image.png")!)
        dataDownloadingSpan.setTag(key: SpanTags.resource, value: "GET /image.png")

        // Simulate downloading data required by the screen.
        downloadScreenData { data in
            // Simulate logging download progress
            dataDownloadingSpan.log(
                fields: [
                    OTLogFields.message: "download progress",
                    "progress": 0.99
                ]
            )
            dataDownloadingSpan.finish()

            let dataPresentationSpan = tracer.startSpan(operationName: "data presentation")
            Thread.sleep(forTimeInterval: 0.06)
            dataPresentationSpan.setTag(key: OTTags.error, value: true)
            dataPresentationSpan.setError(NSError(domain: "SendTracesFixtureViewController", code: 1, userInfo: nil))
            dataPresentationSpan.finish()

            viewLoadingSpan.finish()
        }
    }

    /// Simulates downloading data required to build the UI for the screen.
    private func downloadScreenData(completion: @escaping (Data) -> Void) {
        backgroundQueue.async {
            Thread.sleep(forTimeInterval: 0.3)
            DispatchQueue.main.async { completion(Data()) }
        }
    }
}
