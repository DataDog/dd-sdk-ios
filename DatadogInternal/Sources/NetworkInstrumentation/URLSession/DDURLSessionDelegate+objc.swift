/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@objcMembers
@_spi(objc)
@available(*, deprecated, message: "Use `URLSessionInstrumentation.enable(with:)` instead.")
open class DDNSURLSessionDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    override public init() {
        URLSessionInstrumentation.enable(
            with: .init(
                delegateClass: Self.self
            ),
            in: CoreRegistry.default
        )
        super.init()
    }

    public init(additionalFirstPartyHostsWithHeaderTypes: [String: Set<objc_TracingHeaderType>]) {
        URLSessionInstrumentation.enable(
            with: .init(
                delegateClass: Self.self,
                firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: additionalFirstPartyHostsWithHeaderTypes.mapValues { tracingHeaderTypes in
                    return Set(tracingHeaderTypes.map { $0.swiftType })
                })
            ),
            in: CoreRegistry.default
        )
        super.init()
    }

    public convenience init(additionalFirstPartyHosts: Set<String>) {
        self.init(
            additionalFirstPartyHostsWithHeaderTypes: additionalFirstPartyHosts.reduce(into: [:], { partialResult, host in
                partialResult[host] = [.datadog, .tracecontext]
            })
        )
    }
}
