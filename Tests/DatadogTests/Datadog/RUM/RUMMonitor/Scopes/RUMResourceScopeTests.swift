/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMResourceScopeTests: XCTestCase {
    private let output = RUMEventOutputMock()
    private let randomServiceName: String = .mockRandom()
    private lazy var dependencies: RUMScopeDependencies = .mockWith(
        serviceName: randomServiceName,
        eventOutput: output
    )
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertValidRumUUID(event.resource.id)
        XCTAssertEqual(event.resource.type, .image)
        XCTAssertEqual(event.resource.method, .post)
        XCTAssertNil(event.resource.provider)
        XCTAssertEqual(event.resource.url, "https://foo.com/resource/1")
        XCTAssertEqual(event.resource.statusCode, 200)
        XCTAssertEqual(event.resource.duration, 2_000_000_000)
        XCTAssertEqual(event.resource.size, 1_024)
        XCTAssertNil(event.resource.redirect)
        XCTAssertNil(event.resource.dns)
        XCTAssertNil(event.resource.connect)
        XCTAssertNil(event.resource.ssl)
        XCTAssertNil(event.resource.firstByte)
        XCTAssertNil(event.resource.download)
        XCTAssertEqual(try XCTUnwrap(event.action?.id), context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.traceId, "100")
        XCTAssertEqual(event.dd.spanId, "200")
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.service, randomServiceName)
    }

    func testGivenConfiguredSoruce_whenResourceLoadingEnds_itSendsResourceEventWithCorrecSource() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let customSource = String.mockAnySource()
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies.replacing(
                source: customSource
            ),
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.source, RUMResourceEvent.Source(rawValue: customSource))
    }

    func testGivenStartedResource_whenResourceLoadingEndsWithNegativeDuration_itSendsResourceEventWithPositiveDuration() throws {
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

        currentTime.addTimeInterval(-1)

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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertValidRumUUID(event.resource.id)
        XCTAssertEqual(event.resource.type, .image)
        XCTAssertEqual(event.resource.method, .post)
        XCTAssertNil(event.resource.provider)
        XCTAssertEqual(event.resource.url, "https://foo.com/resource/1")
        XCTAssertEqual(event.resource.statusCode, 200)
        XCTAssertEqual(event.resource.duration, 1)
        XCTAssertEqual(event.resource.size, 1_024)
        XCTAssertNil(event.resource.redirect)
        XCTAssertNil(event.resource.dns)
        XCTAssertNil(event.resource.connect)
        XCTAssertNil(event.resource.ssl)
        XCTAssertNil(event.resource.firstByte)
        XCTAssertNil(event.resource.download)
        XCTAssertEqual(try XCTUnwrap(event.action?.id), context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.traceId, "100")
        XCTAssertEqual(event.dd.spanId, "200")
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.service, randomServiceName)
    }

    func testGivenStartedResource_whenResourceLoadingEnds_itSendsResourceEventWithCustomSpanAndTraceId() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [CrossPlatformAttributes.traceID: "100", CrossPlatformAttributes.spanID: "200"],
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertValidRumUUID(event.resource.id)
        XCTAssertEqual(event.resource.type, .image)
        XCTAssertEqual(event.resource.method, .post)
        XCTAssertNil(event.resource.provider)
        XCTAssertEqual(event.resource.url, "https://foo.com/resource/1")
        XCTAssertEqual(event.resource.statusCode, 200)
        XCTAssertEqual(event.resource.duration, 2_000_000_000)
        XCTAssertEqual(event.resource.size, 1_024)
        XCTAssertNil(event.resource.redirect)
        XCTAssertNil(event.resource.dns)
        XCTAssertNil(event.resource.connect)
        XCTAssertNil(event.resource.ssl)
        XCTAssertNil(event.resource.firstByte)
        XCTAssertNil(event.resource.download)
        XCTAssertEqual(try XCTUnwrap(event.action?.id), context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.traceId, "100")
        XCTAssertEqual(event.dd.spanId, "200")
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, randomServiceName)
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(event.date, currentTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertEqual(event.error.type, "ErrorMock")
        XCTAssertEqual(event.error.message, "network issue explanation")
        XCTAssertEqual(event.error.source, .network)
        XCTAssertEqual(event.error.stack, "network issue explanation")
        XCTAssertEqual(event.error.resource?.method, .post)
        XCTAssertEqual(event.error.type, "ErrorMock")
        XCTAssertNil(event.error.resource?.provider)
        XCTAssertEqual(event.error.resource?.statusCode, 500)
        XCTAssertEqual(event.error.resource?.url, "https://foo.com/resource/1")
        XCTAssertEqual(try XCTUnwrap(event.action?.id), context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, randomServiceName)
    }

    func testGivenConfiguredSource_whenResourceLoadingEndsWithError_itSendsErrorEventWithConfiguredSource() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let customSource = String.mockAnySource()
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies.replacing(
                source: customSource
            ),
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(event.source, RUMErrorEvent.Source(rawValue: customSource))
        XCTAssertEqual(event.service, randomServiceName)
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.date, metrics.fetch.start.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.view.id, context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertValidRumUUID(event.resource.id)
        XCTAssertEqual(event.resource.type, .image)
        XCTAssertEqual(event.resource.method, .post)
        XCTAssertEqual(event.resource.url, "https://foo.com/resource/1")
        XCTAssertEqual(event.resource.statusCode, 200)
        XCTAssertEqual(event.resource.duration, 10_000_000_000)
        XCTAssertEqual(event.resource.size, 2_048)
        XCTAssertEqual(event.resource.redirect?.start, 1_000_000_000)
        XCTAssertEqual(event.resource.redirect?.duration, 1_000_000_000)
        XCTAssertEqual(event.resource.dns?.start, 3_000_000_000)
        XCTAssertEqual(event.resource.dns?.duration, 1_000_000_000)
        XCTAssertEqual(event.resource.connect?.start, 5_000_000_000)
        XCTAssertEqual(event.resource.connect?.duration, 2_000_000_000)
        XCTAssertEqual(event.resource.ssl?.start, 6_000_000_000)
        XCTAssertEqual(event.resource.ssl?.duration, 1_000_000_000)
        XCTAssertEqual(event.resource.firstByte?.start, 8_000_000_000)
        XCTAssertEqual(event.resource.firstByte?.duration, 1_000_000_000)
        XCTAssertEqual(event.resource.download?.start, 9_000_000_000)
        XCTAssertEqual(event.resource.download?.duration, 1_000_000_000)
        XCTAssertEqual(try XCTUnwrap(event.action?.id), context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertNil(event.dd.traceId)
        XCTAssertNil(event.dd.spanId)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, randomServiceName)
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
        let resourceEvents = try output.recordedEvents(ofType: RUMResourceEvent.self)
        let resource1Events = resourceEvents.filter { $0.resource.url == "/r/1" }
        let resource2Events = resourceEvents.filter { $0.resource.url == "/r/2" }
        XCTAssertEqual(resource1Events.count, 1)
        XCTAssertEqual(resource2Events.count, 1)
        XCTAssertNotEqual(resource1Events[0].resource.id, resource2Events[0].resource.id)
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.resource.type, kindBasedOnRequest)
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMResourceEvent.self).first)
        let providerType = try XCTUnwrap(event.resource.provider?.type)
        let providerDomain = try XCTUnwrap(event.resource.provider?.domain)
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMResourceEvent.self).first)
        XCTAssertNil(event.resource.provider)
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMErrorEvent.self).first)
        let providerType = try XCTUnwrap(event.error.resource?.provider?.type)
        let providerDomain = try XCTUnwrap(event.error.resource?.provider?.domain)
        XCTAssertEqual(providerType, .firstParty)
        XCTAssertEqual(providerDomain, "foo.com")
        XCTAssertEqual(event.error.sourceType, .ios)
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
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMErrorEvent.self).first)
        XCTAssertNil(event.error.resource?.provider)
        XCTAssertEqual(event.error.sourceType, .ios)
    }

    func testGivenStartedResource_whenResourceLoadingEndsWithErrorWithCustomSourceType_itSendsErrorEventWithCustomSourceType() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let resourceKey = "/resource/1"
        // Given
        let scope = RUMResourceScope.mockWith(
            context: context,
            dependencies: dependencies,
            resourceKey: resourceKey,
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
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(
                    resourceKey: resourceKey,
                    time: currentTime,
                    attributes: [CrossPlatformAttributes.errorSourceType: "react-native"]
                )
            )
        )

        // Then
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(event.error.sourceType, .reactNative)
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
        XCTAssertNotNil(try (output.recordedEvents(ofType: RUMResourceEvent.self).first))
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
        XCTAssertNil(try (output.recordedEvents(ofType: RUMResourceEvent.self).first))
        XCTAssertFalse(onResourceEventSentCalled)
        XCTAssertFalse(onErrorEventSentCalled)
    }
}
