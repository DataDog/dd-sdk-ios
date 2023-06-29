/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogCore
import DatadogInternal

@objc
open class DDNSURLSessionDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, __URLSessionDelegateProviding {
    var swiftDelegate: DDURLSessionDelegate
    public var ddURLSessionDelegate: DatadogURLSessionDelegate {
        return swiftDelegate
    }

    @objc
    override public init() {
        swiftDelegate = DDURLSessionDelegate()
    }

    @objc
    public init(additionalFirstPartyHostsWithHeaderTypes: [String: Set<DDTracingHeaderType>]) {
        swiftDelegate = DDURLSessionDelegate(
            additionalFirstPartyHostsWithHeaderTypes: additionalFirstPartyHostsWithHeaderTypes.mapValues { tracingHeaderTypes in
                return Set(tracingHeaderTypes.map { $0.swiftType })
            }
        )
    }

    @objc
    public init(additionalFirstPartyHosts: Set<String>) {
        swiftDelegate = DDURLSessionDelegate(additionalFirstPartyHosts: additionalFirstPartyHosts)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        swiftDelegate.urlSession(session, task: task, didCompleteWithError: error)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        swiftDelegate.urlSession(session, task: task, didFinishCollecting: metrics)
    }

    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        swiftDelegate.urlSession(session, dataTask: dataTask, didReceive: data)
    }
}
