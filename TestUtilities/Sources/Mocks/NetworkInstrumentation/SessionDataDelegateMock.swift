/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public final class SessionDataDelegateMock: NSObject, URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) { }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { }
}
