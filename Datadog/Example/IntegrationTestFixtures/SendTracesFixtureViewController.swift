/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import OpenTracing
import struct Datadog.DDTags

internal class SendTracesFixtureViewController: UIViewController {
    private let backgroundQueue = DispatchQueue(label: "background-queue")

    /// Traces view appearing
    private var viewAppearingSpan: Span!

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
