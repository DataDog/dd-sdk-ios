/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension SpanID: AnyMockable, RandomMockable {
    public static func mockAny() -> SpanID {
        return SpanID(rawValue: .mockAny())
    }

    public static func mockRandom() -> SpanID {
        return SpanID(rawValue: .mockRandom())
    }

    public static func mock(_ rawValue: UInt64) -> SpanID {
        return SpanID(rawValue: rawValue)
    }
}

extension TraceID: AnyMockable, RandomMockable {
    public static func mockAny() -> TraceID {
        return TraceID(rawValue: (.mockAny(), .mockAny()))
    }

    public static func mockRandom() -> TraceID {
        return TraceID(idHi: .mockRandom(), idLo: .mockRandom())
    }

    public static func mock(_ rawValue: (UInt64, UInt64)) -> TraceID {
        return TraceID(rawValue: rawValue)
    }

    public static func mock(_ idHi: UInt64, _ idLo: UInt64) -> TraceID {
        return TraceID(idHi: idHi, idLo: idLo)
    }

    public static func mock(_ idLo: UInt64) -> TraceID {
        return TraceID(idLo: idLo)
    }
}

extension TraceContext: AnyMockable, RandomMockable {
    public static func mockAny() -> TraceContext {
        return .mockWith()
    }

    public static func mockRandom() -> TraceContext {
        return .mockWith(
            traceID: .mockRandom(),
            spanID: .mockRandom(),
            parentSpanID: .mockRandom(),
            sampleRate: .mockRandom(min: 0, max: 100),
            samplingPriority: .mockRandom(),
            samplingDecisionMaker: .mockRandom()
        )
    }

    public static func mockWith(
        traceID: TraceID = .mockAny(),
        spanID: SpanID = .mockAny(),
        parentSpanID: SpanID? = nil,
        sampleRate: Float = .mockAny(),
        samplingPriority: SamplingPriority = .mockAny(),
        samplingDecisionMaker: SamplingMechanismType = .mockAny(),
        rumSessionId: String? = .mockAny()
    ) -> TraceContext {
        return TraceContext(
            traceID: traceID,
            spanID: spanID,
            parentSpanID: parentSpanID,
            sampleRate: sampleRate,
            samplingPriority: samplingPriority,
            samplingDecisionMaker: samplingDecisionMaker,
            rumSessionId: rumSessionId
        )
    }
}

public class RelativeTracingUUIDGenerator: TraceIDGenerator {
    private(set) var uuid: TraceID
    internal let count: UInt64
    private let queue = DispatchQueue(label: "queue-RelativeTracingUUIDGenerator-\(UUID().uuidString)")

    public init(startingFrom uuid: TraceID, advancingByCount count: UInt64 = 1) {
        self.uuid = uuid
        self.count = count
    }

    public func generate() -> TraceID {
        return queue.sync {
            defer { uuid = uuid + (0, count) }
            return uuid
        }
    }
}

public class RelativeSpanIDGenerator: SpanIDGenerator {
    @ReadWriteLock
    private(set) var uuid: SpanID
    internal let count: UInt64

    public init(startingFrom uuid: SpanID, advancingByCount count: UInt64 = 1) {
        self.uuid = uuid
        self.count = count
    }

    public func generate() -> SpanID {
        defer { uuid = uuid + count }
        return uuid
    }
}

private func + (lhs: SpanID, rhs: UInt64) -> SpanID {
    return SpanID(rawValue: lhs.rawValue + rhs)
}

private func + (lhs: TraceID, rhs: (UInt64, UInt64)) -> TraceID {
    return TraceID(rawValue: (lhs.rawValue.0 + rhs.0, lhs.rawValue.1 + rhs.1))
}

extension URLSession {
    public static func mockWith(_ delegate: URLSessionDelegate) -> URLSession {
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }
}

public final class URLSessionHandlerMock: DatadogURLSessionHandler {
    public var firstPartyHosts: FirstPartyHosts

    public var modifiedRequest: URLRequest?
    public var injectedTraceContext: TraceContext?
    public var shouldInterceptRequest: ((URLRequest) -> Bool)?

    public var onRequestMutation: ((URLRequest, Set<TracingHeaderType>, NetworkContext?) -> Void)?
    public var onRequestInterception: ((URLRequest) -> Void)?
    public var onInterceptionDidStart: ((URLSessionTaskInterception) -> Void)?
    public var onInterceptionDidComplete: ((URLSessionTaskInterception) -> Void)?

    @ReadWriteLock
    public private(set) var interceptions: [UUID: URLSessionTaskInterception] = [:]

    public init(firstPartyHosts: FirstPartyHosts = .init()) {
        self.firstPartyHosts = firstPartyHosts
    }

    public func interception(for request: URLRequest) -> URLSessionTaskInterception? {
        interceptions.values.first { $0.request.unsafeOriginal == request }
    }

    public func interception(for url: URL) -> URLSessionTaskInterception? {
        interceptions.values.first { $0.request.url == url }
    }

    public func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>, networkContext: NetworkContext?) -> (URLRequest, TraceContext?, URLSessionHandlerCapturedState?) {
        onRequestMutation?(request, headerTypes, networkContext)
        return (modifiedRequest ?? request, injectedTraceContext, nil)
    }

    public func interceptionDidStart(interception: URLSessionTaskInterception, capturedStates: [any URLSessionHandlerCapturedState]) {
        onInterceptionDidStart?(interception)
        interceptions[interception.identifier] = interception
    }

    public func interceptionDidComplete(interception: URLSessionTaskInterception) {
        onInterceptionDidComplete?(interception)
        interceptions[interception.identifier] = interception
    }
}

extension ResourceCompletion: AnyMockable {
    public static func mockAny() -> Self {
        return mockWith()
    }

    public static func mockWith(
        response: URLResponse? = .mockAny(),
        error: Error? = nil
    ) -> Self {
        return ResourceCompletion(response: response, error: error)
    }
}

extension ImmutableRequest: AnyMockable {
    public static func mockAny() -> ImmutableRequest {
        return .mockWith()
    }
    public static func mockWith(
        url: URL = .mockAny(),
        httpMethod: String = "GET",
        allHTTPHeaderFields: [String: String] = .mockAny()
    ) -> ImmutableRequest {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.allHTTPHeaderFields = allHTTPHeaderFields
        return ImmutableRequest(request: request)
    }
}

extension ResourceMetrics: AnyMockable {
    public static func mockAny() -> Self {
        return mockWith()
    }

    public static func mockWith(
        fetch: DateInterval = .init(start: Date(), end: Date(timeIntervalSinceNow: 1)),
        redirection: DateInterval? = nil,
        dns: DateInterval? = nil,
        connect: DateInterval? = nil,
        ssl: DateInterval? = nil,
        firstByte: DateInterval? = nil,
        download: DateInterval? = nil,
        responseSize: Int64? = nil
    ) -> Self {
        return .init(
            fetch: fetch,
            redirection: redirection,
            dns: dns,
            connect: connect,
            ssl: ssl,
            firstByte: firstByte,
            download: download,
            responseSize: responseSize
        )
    }
}

extension TrackingMode: AnyMockable, RandomMockable {
    public static func mockAny() -> DatadogInternal.TrackingMode {
        return .automatic
    }

    public static func mockRandom() -> DatadogInternal.TrackingMode {
        return [.automatic, .registeredDelegate].randomElement()!
    }
}
