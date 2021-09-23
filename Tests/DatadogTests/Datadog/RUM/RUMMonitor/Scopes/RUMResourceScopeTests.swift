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
        activeViewPath: "FooViewController",
        activeViewName: "FooViewName",
        activeUserActionID: .mockRandom()
    )

    func testDefaultContext() {
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: .mockAny(),
            resourceKey: .mockAny(),
            attributes: [:],
            startTime: .mockAny(),
            dateCorrection: .zero
        )

        XCTAssertEqual(scope.context.rumApplicationID, context.rumApplicationID)
        XCTAssertEqual(scope.context.sessionID, context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, try XCTUnwrap(context.activeViewID))
        XCTAssertEqual(scope.context.activeViewPath, try XCTUnwrap(context.activeViewPath))
        XCTAssertEqual(scope.context.activeUserActionID, try XCTUnwrap(context.activeUserActionID))
    }

    func testGivenStartedResource_whenResourceLoadingEnds_itSendsResourceEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: nil,
            resourceKindBasedOnRequest: nil,
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertEqual(event.model.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertEqual(event.model.view.name, "FooViewName")
        XCTAssertValidRumUUID(event.model.resource.id)
        XCTAssertEqual(event.model.resource.type, .image)
        XCTAssertEqual(event.model.resource.method, .post)
        XCTAssertNil(event.model.resource.provider)
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
        XCTAssertEqual(event.model.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.model.dd.traceId, "100")
        XCTAssertEqual(event.model.dd.spanId, "200")
        XCTAssertEqual(event.model.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
    }

    func testGivenStartedResource_whenResourceLoadingEnds_itSendsResourceEventWithCustomSpanAndTraceId() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: ["_dd.trace_id": "100", "_dd.span_id": "200"],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: nil,
            resourceKindBasedOnRequest: nil,
            spanContext: nil
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertEqual(event.model.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertEqual(event.model.view.name, "FooViewName")
        XCTAssertValidRumUUID(event.model.resource.id)
        XCTAssertEqual(event.model.resource.type, .image)
        XCTAssertEqual(event.model.resource.method, .post)
        XCTAssertNil(event.model.resource.provider)
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
        XCTAssertEqual(event.model.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.model.dd.traceId, "100")
        XCTAssertEqual(event.model.dd.spanId, "200")
    }

    func testGivenStartedResource_whenResourceLoadingEndsWithError_itSendsErrorEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/1",
            httpMethod: .post
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMErrorEvent>.self).first)
        XCTAssertEqual(event.model.date, currentTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertEqual(event.model.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertEqual(event.model.view.name, "FooViewName")
        XCTAssertEqual(event.model.error.type, "ErrorMock")
        XCTAssertEqual(event.model.error.message, "network issue explanation")
        XCTAssertEqual(event.model.error.source, .network)
        XCTAssertEqual(event.model.error.stack, "network issue explanation")
        XCTAssertEqual(event.model.error.resource?.method, .post)
        XCTAssertEqual(event.model.error.type, "ErrorMock")
        XCTAssertNil(event.model.error.resource?.provider)
        XCTAssertEqual(event.model.error.resource?.statusCode, 500)
        XCTAssertEqual(event.model.error.resource?.url, "https://foo.com/resource/1")
        XCTAssertEqual(try XCTUnwrap(event.model.action?.id), context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.model.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.model.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
    }

    func testGivenStartedResource_whenResourceReceivesMetricsBeforeItEnds_itUsesMetricValuesInSentResourceEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/1",
            httpMethod: .post
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self).first)
        XCTAssertEqual(event.model.date, metrics.fetch.start.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertEqual(event.model.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertEqual(event.model.view.name, "FooViewName")
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
        XCTAssertEqual(event.model.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertNil(event.model.dd.traceId)
        XCTAssertNil(event.model.dd.spanId)
    }

    func testGivenMultipleResourceScopes_whenSendingResourceEvents_eachEventHasUniqueResourceID() throws {
        let resourceKey: String = .mockAny()
        func createScope(url: String) -> RUMResourceScope {
            RUMResourceScope.mockWith(
                context: context,
                dependencies: dependencies,
                resourceKey: resourceKey,
                attributes: [:],
                startTime: .mockAny(),
                dateCorrection: .zero,
                url: url
            )
        }

        let scope1 = createScope(url: "/r/1")
        let scope2 = createScope(url: "/r/2")

        // When
        _ = scope1.process(command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey))
        _ = scope2.process(command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey))

        // Then
        let resourceEvents = try output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self)
        let resource1Events = resourceEvents.filter { $0.model.resource.url == "/r/1" }
        let resource2Events = resourceEvents.filter { $0.model.resource.url == "/r/2" }
        XCTAssertEqual(resource1Events.count, 1)
        XCTAssertEqual(resource2Events.count, 1)
        XCTAssertNotEqual(resource1Events[0].model.resource.id, resource2Events[0].model.resource.id)
    }

    func testGivenResourceStartedWithKindBasedOnRequest_whenLoadingEndsWithDifferentKind_itSendsTheKindBasedOnRequest() throws {
        let kinds: [RUMResourceType] = [.image, .xhr, .beacon, .css, .document, .fetch, .font, .js, .media, .other, .native]
        let kindBasedOnRequest = kinds.randomElement()!
        let kindBasedOnResponse = kinds.randomElement()!

        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: Date(),
            dateCorrection: .zero,
            url: .mockAny(),
            httpMethod: .post,
            isFirstPartyResource: nil,
            resourceKindBasedOnRequest: kindBasedOnRequest
        )

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand.mockWith(
                    resourceKey: "/resource/1",
                    kind: kindBasedOnResponse
                )
            )
        )

        // Then
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self).first)
        XCTAssertEqual(event.model.resource.type, kindBasedOnRequest)
    }

    func testGivenStartedFirstPartyResource_whenResourceLoadingEnds_itSendsResourceEventWithFirstPartyProvider() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: true,
            resourceKindBasedOnRequest: nil,
            spanContext: .init(traceID: "100", spanID: "200")
        )

        currentTime.addTimeInterval(2)

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1")
            )
        )

        // Then
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self).first)
        let providerType = try XCTUnwrap(event.model.resource.provider?.type)
        let providerDomain = try XCTUnwrap(event.model.resource.provider?.domain)
        XCTAssertEqual(providerType, .firstParty)
        XCTAssertEqual(providerDomain, "foo.com")
    }

    func testGivenStartedThirdartyResource_whenResourceLoadingEnds_itSendsResourceEventWithoutResourceProvider() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: false,
            resourceKindBasedOnRequest: nil,
            spanContext: .init(traceID: "100", spanID: "200")
        )

        currentTime.addTimeInterval(2)

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1")
            )
        )

        // Then
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self).first)
        XCTAssertNil(event.model.resource.provider)
    }

    func testGivenStartedFirstPartyResource_whenResourceLoadingEndsWithError_itSendsErrorEventWithFirstPartyProvider() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: true
        )

        currentTime.addTimeInterval(2)

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/1")
            )
        )

        // Then
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMErrorEvent>.self).first)
        let providerType = try XCTUnwrap(event.model.error.resource?.provider?.type)
        let providerDomain = try XCTUnwrap(event.model.error.resource?.provider?.domain)
        XCTAssertEqual(providerType, .firstParty)
        XCTAssertEqual(providerDomain, "foo.com")
    }

    func testGivenStartedThirdPartyResource_whenResourceLoadingEndsWithError_itSendsErrorEventWithoutResourceProvider() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: false
        )

        currentTime.addTimeInterval(2)

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/1")
            )
        )

        // Then
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMErrorEvent>.self).first)
        XCTAssertNil(event.model.error.resource?.provider)
    }

    // MARK: - Events sending callbacks

    func testGivenResourceScopeWithDefaultEventsMapper_whenSendingEvents_thenEventSentCallbacksAreCalled() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        var onResourceEventSentCalled = false
        var onErrorEventSentCalled = false
        // Given
        let scope1 = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: nil,
            resourceKindBasedOnRequest: nil,
            spanContext: .init(traceID: "100", spanID: "200"),
            onResourceEventSent: {
                onResourceEventSentCalled = true
            }
        )

        let scope2 = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/2",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/2",
            httpMethod: .post,
            isFirstPartyResource: nil,
            resourceKindBasedOnRequest: nil,
            spanContext: .init(traceID: "100", spanID: "200"),
            onErrorEventSent: {
                onErrorEventSentCalled = true
            }
        )

        // When
        XCTAssertFalse(
            scope1.process(
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

        XCTAssertFalse(
            scope2.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2")
            )
        )

        // Then
        XCTAssertNotNil(try (output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self).first))
        XCTAssertTrue(onResourceEventSentCalled)
        XCTAssertTrue(onErrorEventSentCalled)
    }

    func testGivenResourceScopeWithDroppingEventsMapper_whenBypassingSendingEvents_thenEventSentCallbacksAreNotCalled() {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        var onResourceEventSentCalled = false
        var onErrorEventSentCalled = false

        // Given
        let eventBuilder = RUMEventBuilder(
            eventsMapper: RUMEventsMapper.mockWith(
                errorEventMapper: { event in
                    nil
                },
                resourceEventMapper: { event in
                    nil
                }
            )
        )
        let dependencies: RUMScopeDependencies = .mockWith(eventBuilder: eventBuilder, eventOutput: output)

        // swiftlint:disable trailing_closure
        let scope1 = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: nil,
            resourceKindBasedOnRequest: nil,
            spanContext: .init(traceID: "100", spanID: "200"),
            onResourceEventSent: {
                onResourceEventSentCalled = true
            }
        )

        let scope2 = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/2",
            attributes: [:],
            startTime: currentTime,
            dateCorrection: .zero,
            url: "https://foo.com/resource/2",
            httpMethod: .post,
            isFirstPartyResource: nil,
            resourceKindBasedOnRequest: nil,
            spanContext: .init(traceID: "100", spanID: "200"),
            onErrorEventSent: {
                onErrorEventSentCalled = true
            }
        )
        // swiftlint:enable trailing_closure

        // When
        XCTAssertFalse(
            scope1.process(
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

        XCTAssertFalse(
            scope2.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2")
            )
        )

        // Then
        XCTAssertNil(try (output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self).first))
        XCTAssertFalse(onResourceEventSentCalled)
        XCTAssertFalse(onErrorEventSentCalled)
    }
}
