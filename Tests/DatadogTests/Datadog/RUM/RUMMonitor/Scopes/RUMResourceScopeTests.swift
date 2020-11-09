/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMResourceScopeTests: XCTestCase {
    private let output = RUMEventOutputMock()
    private lazy var dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)
    private let context = RUMContext.mockWith(
        rumApplicationID: "rum-123",
        sessionID: .mockRandom(),
        activeViewID: .mockRandom(),
        activeViewURI: "FooViewController",
        activeUserActionID: .mockRandom()
    )

    func testDefaultContext() {
        let scope = RUMResourceScope(
            context: context,
            dependencies: .mockAny(),
            resourceKey: .mockAny(),
            attributes: [:],
            startTime: .mockAny(),
            url: .mockAny(),
            httpMethod: .mockAny(),
            spanContext: nil
        )

        XCTAssertEqual(scope.context.rumApplicationID, context.rumApplicationID)
        XCTAssertEqual(scope.context.sessionID, context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, try XCTUnwrap(context.activeViewID))
        XCTAssertEqual(scope.context.activeViewURI, try XCTUnwrap(context.activeViewURI))
        XCTAssertEqual(scope.context.activeUserActionID, try XCTUnwrap(context.activeUserActionID))
    }

    func testGivenStartedResource_whenResourceLoadingEnds_itSendsResourceEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .POST,
            spanContext: .init(traceID: "100", spanID: "200")
        )

        currentTime.addTimeInterval(2)

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand(
                    resourceKey: "/resource/1",
                    time: currentTime,
                    attributes: ["foo": "bar"],
                    kind: .image,
                    httpStatusCode: 200,
                    size: 1_024
                )
            )
        )

        // Then
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMDataResource>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertEqual(event.model.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertValidRumUUID(event.model.resource.id)
        XCTAssertEqual(event.model.resource.type, .image)
        XCTAssertEqual(event.model.resource.method, .post)
        XCTAssertEqual(event.model.resource.url, "https://foo.com/resource/1")
        XCTAssertEqual(event.model.resource.statusCode, 200)
        XCTAssertEqual(event.model.resource.duration, 2_000_000_000)
        XCTAssertEqual(event.model.resource.size, 1_024)
        XCTAssertNil(event.model.resource.redirect)
        XCTAssertNil(event.model.resource.dns)
        XCTAssertNil(event.model.resource.connect)
        XCTAssertNil(event.model.resource.ssl)
        XCTAssertNil(event.model.resource.firstByte)
        XCTAssertNil(event.model.resource.download)
        XCTAssertEqual(try XCTUnwrap(event.model.action?.id), context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.model.dd.traceID, "100")
        XCTAssertEqual(event.model.dd.spanID, "200")
    }

    func testGivenStartedResource_whenResourceLoadingEndsWithError_itSendsErrorEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .POST,
            spanContext: nil
        )

        currentTime.addTimeInterval(2)

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceWithErrorCommand(
                    resourceKey: "/resource/1",
                    time: currentTime,
                    error: ErrorMock("network issue explanation"),
                    source: .network,
                    httpStatusCode: 500,
                    attributes: ["foo": "bar"]
                )
            )
        )

        // Then
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMDataError>.self).first)
        XCTAssertEqual(event.model.date, currentTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertEqual(event.model.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertEqual(event.model.error.message, "ErrorMock - network issue explanation")
        XCTAssertEqual(event.model.error.source, .network)
        XCTAssertEqual(event.model.error.stack, "description: network issue explanation")
        XCTAssertEqual(event.model.error.resource?.method, .post)
        XCTAssertEqual(event.model.error.resource?.statusCode, 500)
        XCTAssertEqual(event.model.error.resource?.url, "https://foo.com/resource/1")
        XCTAssertEqual(try XCTUnwrap(event.model.action?.id), context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar"])
    }

    func testGivenStartedResource_whenResourceReceivesMetricsBeforeItEnds_itUsesMetricValuesInSentResourceEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .POST,
            spanContext: nil
        )

        currentTime.addTimeInterval(2)

        // When
        let resourceFetchStart = Date()
        let metricsCommand = RUMAddResourceMetricsCommand(
            resourceKey: "/resource/1",
            time: currentTime,
            attributes: [:],
            metrics: .mockWith(
                fetch: .init(
                    start: resourceFetchStart,
                    end: resourceFetchStart.addingTimeInterval(10)
                ),
                redirection: .init(
                    start: resourceFetchStart.addingTimeInterval(1),
                    end: resourceFetchStart.addingTimeInterval(2)
                ),
                dns: .init(
                    start: resourceFetchStart.addingTimeInterval(3),
                    end: resourceFetchStart.addingTimeInterval(4)
                ),
                connect: .init(
                    start: resourceFetchStart.addingTimeInterval(5),
                    end: resourceFetchStart.addingTimeInterval(7)
                ),
                ssl: .init(
                    start: resourceFetchStart.addingTimeInterval(6),
                    end: resourceFetchStart.addingTimeInterval(7)
                ),
                firstByte: .init(
                    start: resourceFetchStart.addingTimeInterval(8),
                    end: resourceFetchStart.addingTimeInterval(9)
                ),
                download: .init(
                    start: resourceFetchStart.addingTimeInterval(9),
                    end: resourceFetchStart.addingTimeInterval(10)
                ),
                responseSize: 2_048
            )
        )

        XCTAssertTrue(scope.process(command: metricsCommand))

        currentTime.addTimeInterval(1)

        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand(
                    resourceKey: "/resource/1",
                    time: currentTime,
                    attributes: ["foo": "bar"],
                    kind: .image,
                    httpStatusCode: 200,
                    size: 1_024
                )
            )
        )

        // Then
        let metrics = metricsCommand.metrics
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMDataResource>.self).first)
        XCTAssertEqual(event.model.date, metrics.fetch.start.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertEqual(event.model.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertValidRumUUID(event.model.resource.id)
        XCTAssertEqual(event.model.resource.type, .image)
        XCTAssertEqual(event.model.resource.method, .post)
        XCTAssertEqual(event.model.resource.url, "https://foo.com/resource/1")
        XCTAssertEqual(event.model.resource.statusCode, 200)
        XCTAssertEqual(event.model.resource.duration, 10_000_000_000)
        XCTAssertEqual(event.model.resource.size, 2_048)
        XCTAssertEqual(event.model.resource.redirect?.start, 1_000_000_000)
        XCTAssertEqual(event.model.resource.redirect?.duration, 1_000_000_000)
        XCTAssertEqual(event.model.resource.dns?.start, 3_000_000_000)
        XCTAssertEqual(event.model.resource.dns?.duration, 1_000_000_000)
        XCTAssertEqual(event.model.resource.connect?.start, 5_000_000_000)
        XCTAssertEqual(event.model.resource.connect?.duration, 2_000_000_000)
        XCTAssertEqual(event.model.resource.ssl?.start, 6_000_000_000)
        XCTAssertEqual(event.model.resource.ssl?.duration, 1_000_000_000)
        XCTAssertEqual(event.model.resource.firstByte?.start, 8_000_000_000)
        XCTAssertEqual(event.model.resource.firstByte?.duration, 1_000_000_000)
        XCTAssertEqual(event.model.resource.download?.start, 9_000_000_000)
        XCTAssertEqual(event.model.resource.download?.duration, 1_000_000_000)
        XCTAssertEqual(try XCTUnwrap(event.model.action?.id), context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar"])
        XCTAssertNil(event.model.dd.traceID)
        XCTAssertNil(event.model.dd.spanID)
    }

    func testGivenMultipleResourceScopes_whenSendingResourceEvents_eachEventHasUniqueResourceID() throws {
        let resourceKey: String = .mockAny()
        func createScope(url: String) -> RUMResourceScope {
            RUMResourceScope(
                context: context,
                dependencies: dependencies,
                resourceKey: resourceKey,
                attributes: [:],
                startTime: .mockAny(),
                url: url,
                httpMethod: .mockAny(),
                spanContext: nil
            )
        }

        let scope1 = createScope(url: "/r/1")
        let scope2 = createScope(url: "/r/2")

        // When
        _ = scope1.process(command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey))
        _ = scope2.process(command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey))

        // Then
        let resourceEvents = try output.recordedEvents(ofType: RUMEvent<RUMDataResource>.self)
        let resource1Events = resourceEvents.filter { $0.model.resource.url == "/r/1" }
        let resource2Events = resourceEvents.filter { $0.model.resource.url == "/r/2" }
        XCTAssertEqual(resource1Events.count, 1)
        XCTAssertEqual(resource2Events.count, 1)
        XCTAssertNotEqual(resource1Events[0].model.resource.id, resource2Events[0].model.resource.id)
    }
}
