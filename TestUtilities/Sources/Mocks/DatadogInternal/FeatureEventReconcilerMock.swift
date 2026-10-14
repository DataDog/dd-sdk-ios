/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public final class FeatureEventReconcilerMock: FeatureEventReconciler {
    public typealias Response = Set<Int>

    public var reconciliationStub: ([Event], DatadogContext, ExecutionContext) throws -> EventReconciliation = { _, _, _ in .skip }
    public var responseStub: (Data?, HTTPURLResponse) throws -> Response = { _, _ in [] }
    public var eventsStub: ([Event], Response) throws -> [Event] = { events, _ in events }
    public var requestStub: ([Event], DatadogContext, ExecutionContext) throws -> URLRequest = { _, _, _ in .mockAny() }

    public init() {}

    public func reconciliation(for events: [Event], with context: DatadogContext, execution: ExecutionContext) throws -> EventReconciliation {
        try reconciliationStub(events, context, execution)
    }

    public func response(from data: Data?, with response: HTTPURLResponse) throws -> Response {
        try responseStub(data, response)
    }

    public func events(from events: [Event], using response: Response) throws -> [Event] {
        try eventsStub(events, response)
    }

    public func request(for events: [Event], with context: DatadogContext, execution: ExecutionContext) throws -> URLRequest {
        try requestStub(events, context, execution)
    }
}
