/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import OpenTracing

internal class SendTracesFixtureViewController: UIViewController {
    private let backgroundQueue = DispatchQueue(label: "background-queue")

    /// Traces view appearing
    private var viewAppearingSpan: Span!

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        viewAppearingSpan = tracer.startSpan(operationName: "view appearing", childOf: nil)

        let dataDownloadingSpan = tracer.startSpan(
            operationName: "data downloading",
            childOf: viewAppearingSpan.context
        )

        downloadSomeData { [weak self] data in
            dataDownloadingSpan.finish()

            guard let self = self else { return }

            let dataPresentationSpan = tracer.startSpan(
                operationName: "data presentation",
                childOf: self.viewAppearingSpan.context
            )
            self.present(data: data)
            dataPresentationSpan.finish()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        viewAppearingSpan.finish()
    }

    /// Simulates some asynchronous work with completion.
    private func downloadSomeData(completion: @escaping (Data) -> Void) {
        backgroundQueue.async {
            Thread.sleep(forTimeInterval: 0.3)
            DispatchQueue.main.async { completion(Data()) }
        }
    }

    /// Simulates presentation of some data.
    private func present(data: Data) {
        Thread.sleep(forTimeInterval: 0.06)
    }
}
