/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class SpanBuilderTests: XCTestCase {
    func testItBuildsBasicSpan() throws {
        let builder: SpanBuilder = .mockWith(
            serviceName: "test-service-name"
        )
        let span = try builder.createSpan(
            from: .mockWith(
                context: .mockWith(traceID: 1, spanID: 2, parentSpanID: 1),
                operationName: "operation-name",
                startTime: .mockDecember15th2019At10AMUTC()
            ),
            finishTime: .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.5)
        )

        XCTAssertEqual(span.traceID, 1)
        XCTAssertEqual(span.spanID, 2)
        XCTAssertEqual(span.parentID, 1)
        XCTAssertEqual(span.operationName, "operation-name")
        XCTAssertEqual(span.serviceName, "test-service-name")
        XCTAssertEqual(span.resource, "operation-name") // TODO: RUMM-400 Add separate test for the case when `ddspan.resourceName != nil`
        XCTAssertEqual(span.startTime, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(span.duration, 0.50, accuracy: 0.01)
        XCTAssertFalse(span.isError) // TODO: RUMM-401 Add separate test for the case when `ddspan.isError == true`
        XCTAssertEqual(span.tracerVersion, sdkVersion)
    }

    func testItSetsApplicationVersionAttribute() throws {
        func createSpanUsing(appContext: AppContext) throws -> Span {
            let builder: SpanBuilder = .mockWith(appContext: appContext)
            return try builder.createSpan(
                from: .mockAny(),
                finishTime: .mockAny()
            )
        }

        // When only `bundle.version` is available
        var span = try createSpanUsing(appContext: .mockWith(bundleVersion: "version", bundleShortVersion: nil))
        XCTAssertEqual(span.applicationVersion, "version")

        // When only `bundle.shortVersion` is available
        span = try createSpanUsing(appContext: .mockWith(bundleVersion: nil, bundleShortVersion: "shortVersion"))
        XCTAssertEqual(span.applicationVersion, "shortVersion")

        // When both `bundle.version` and `bundle.shortVersion` are available
        span = try createSpanUsing(appContext: .mockWith(bundleVersion: "version", bundleShortVersion: "shortVersion"))
        XCTAssertEqual(span.applicationVersion, "shortVersion")

        // When neither of `bundle.version` and `bundle.shortVersion` is available
        span = try createSpanUsing(appContext: .mockWith(bundleVersion: nil, bundleShortVersion: nil))
        XCTAssertEqual(span.applicationVersion, "")
    }
}
