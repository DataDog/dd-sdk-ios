/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

internal class Exporter {
    class SessionDelegate: NSObject {}

    let session: URLSession

    init() {
        let configuration: URLSessionConfiguration = .ephemeral
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration, delegate: SessionDelegate(), delegateQueue: nil)
    }
}

extension Exporter.SessionDelegate: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {

    }
}
