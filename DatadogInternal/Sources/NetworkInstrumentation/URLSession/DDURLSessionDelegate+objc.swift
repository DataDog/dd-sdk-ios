/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@objc
@available(*, deprecated, message: "Use `URLSessionInstrumentation.enable(with:)` instead.")
open class DDNSURLSessionDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    @objc
    override public init() {
        URLSessionInstrumentation.enable(
            with: .init(
                delegateClass: Self.self
            ),
            in: CoreRegistry.default
        )
        super.init()
    }

    @objc
    public init(additionalFirstPartyHostsWithHeaderTypes: [String: Set<DDTracingHeaderType>]) {
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

    @objc
    public convenience init(additionalFirstPartyHosts: Set<String>) {
        self.init(
            additionalFirstPartyHostsWithHeaderTypes: additionalFirstPartyHosts.reduce(into: [:], { partialResult, host in
                partialResult[host] = [.datadog, .tracecontext]
            })
        )
    }
}

@objc
public class DDTracingHeaderType: NSObject {
    public let swiftType: TracingHeaderType

    private init(_ swiftType: TracingHeaderType) {
        self.swiftType = swiftType
    }

    @objc public static let datadog = DDTracingHeaderType(.datadog)
    @objc public static let b3multi = DDTracingHeaderType(.b3multi)
    @objc public static let b3 = DDTracingHeaderType(.b3)
    @objc public static let tracecontext = DDTracingHeaderType(.tracecontext)
}
