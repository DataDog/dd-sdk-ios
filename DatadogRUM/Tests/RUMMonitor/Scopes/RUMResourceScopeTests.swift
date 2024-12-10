/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class RUMResourceScopeTests: XCTestCase {
    let context: DatadogContext = .mockWith(
        service: "test-service",
        version: "test-version",
        buildNumber: "test-build",
        buildId: .mockRandom(),
        device: .mockWith(
            name: "device-name",
            osName: "device-os"
        )
    )

    private let dependencies: RUMScopeDependencies = .mockWith(
        firstPartyHosts: FirstPartyHosts(["firstparty.com": [.datadog]])
    )

    private let rumContext = RUMContext.mockWith(
        rumApplicationID: "rum-123",
        sessionID: .mockRandom(),
        activeViewID: .mockRandom(),
        activeViewPath: "FooViewController",
        activeViewName: "FooViewName",
        activeUserActionID: .mockRandom()
    )

    let writer = FileWriterMock()

    func testDefaultContext() {
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: .mockAny(),
            resourceKey: .mockAny(),
            attributes: [:],
            startTime: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, rumContext.rumApplicationID)
        XCTAssertEqual(scope.context.sessionID, rumContext.sessionID)
        XCTAssertEqual(scope.context.activeViewID, try XCTUnwrap(rumContext.activeViewID))
        XCTAssertEqual(scope.context.activeViewPath, try XCTUnwrap(rumContext.activeViewPath))
        XCTAssertEqual(scope.context.activeUserActionID, try XCTUnwrap(rumContext.activeUserActionID))
    }

    func testGivenStartedResource_whenResourceLoadingEnds_itSendsResourceEvent() throws {
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        context.baggages = try .mockSessionReplayAttributes(hasReplay: hasReplay)

        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            resourceKindBasedOnRequest: nil,
            spanContext: .init(
                traceID: .init(idLo: 100),
                spanID: .init(rawValue: 200),
                samplingRate: 0.42
            )
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
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.session.hasReplay, hasReplay)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.view.id, rumContext.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        DDTAssertValidRUMUUID(event.resource.id)
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
        XCTAssertEqual(try XCTUnwrap(event.action?.id.stringValue), rumContext.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.traceId, "64")
        XCTAssertEqual(event.dd.spanId, "200")
        XCTAssertEqual(event.dd.rulePsr, 0.42)
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
    }

    func testGivenStartedResourceInCITest_whenResourceLoadingEnds_itSendsResourceEvent() throws {
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        let fakeCiTestId: String = .mockRandom()
        context.baggages = try .mockSessionReplayAttributes(hasReplay: hasReplay)

        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies.replacing(ciTest: .init(testExecutionId: fakeCiTestId)),
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            resourceKindBasedOnRequest: nil,
            spanContext: .init(
                traceID: .init(idLo: 100),
                spanID: .init(rawValue: 200),
                samplingRate: 0.42
            )
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
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .ciTest)
        XCTAssertEqual(event.session.hasReplay, hasReplay)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.view.id, rumContext.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        DDTAssertValidRUMUUID(event.resource.id)
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
        XCTAssertEqual(try XCTUnwrap(event.action?.id.stringValue), rumContext.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.traceId, "64")
        XCTAssertEqual(event.dd.spanId, "200")
        XCTAssertEqual(event.dd.rulePsr, 0.42)
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.ciTest?.testExecutionId, fakeCiTestId)
    }

    func testGivenStartedResourceInSyntheticsTest_whenResourceLoadingEnds_itSendsResourceEvent() throws {
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        let fakeSyntheticsTestId: String = .mockRandom()
        let fakeSyntheticsResultId: String = .mockRandom()
        context.baggages = try .mockSessionReplayAttributes(hasReplay: hasReplay)

        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies.replacing(syntheticsTest: .init(injected: nil, resultId: fakeSyntheticsResultId, testId: fakeSyntheticsTestId)),
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            resourceKindBasedOnRequest: nil,
            spanContext: .init(
                traceID: .init(idLo: 100),
                spanID: .init(rawValue: 200),
                samplingRate: 0.42
            )
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
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .synthetics)
        XCTAssertEqual(event.session.hasReplay, hasReplay)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.view.id, rumContext.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        DDTAssertValidRUMUUID(event.resource.id)
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
        XCTAssertEqual(try XCTUnwrap(event.action?.id.stringValue), rumContext.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.traceId, "64")
        XCTAssertEqual(event.dd.spanId, "200")
        XCTAssertEqual(event.dd.rulePsr, 0.42)
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.synthetics?.testId, fakeSyntheticsTestId)
        XCTAssertEqual(event.synthetics?.resultId, fakeSyntheticsResultId)
    }

    func testGivenStartedResourceWithSpanContext_whenResourceLoadingEnds_itSendsResourceEvent() throws {
        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            spanContext: .init(
                traceID: .init(idLo: 100),
                spanID: .init(rawValue: 200),
                samplingRate: 0.42
            )
        )

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.dd.traceId, "64")
        XCTAssertEqual(event.dd.spanId, "200")
        XCTAssertEqual(event.dd.rulePsr, 0.42)
    }

    func testGivenStartedResourceWithoutSpanContext_whenResourceLoadingEnds_itSendsResourceEvent() throws {
        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            spanContext: nil
        )

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertNil(event.dd.traceId)
        XCTAssertNil(event.dd.spanId)
        XCTAssertNil(event.dd.rulePsr)
    }

    func testGivenConfiguredSoruce_whenResourceLoadingEnds_itSendsResourceEventWithCorrecSource() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let customSource: String = .mockAnySource()
        let customContext: DatadogContext = .mockWith(source: customSource)

        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post
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
                ),
                context: customContext,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.source, .init(rawValue: customSource))
    }

    func testGivenStartedResource_whenResourceLoadingEndsWithNegativeDuration_itSendsResourceEventWithPositiveDuration() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post
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
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.view.id, rumContext.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        DDTAssertValidRUMUUID(event.resource.id)
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
        XCTAssertEqual(try XCTUnwrap(event.action?.id.stringValue), rumContext.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
    }

    func testGivenStartedResource_whenResourceLoadingEnds_itSendsResourceEventWithCustomSpanAndTraceId() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            attributes: [
                CrossPlatformAttributes.traceID: "100",
                CrossPlatformAttributes.spanID: "200",
                CrossPlatformAttributes.rulePSR: 0.12,
            ],
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post
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
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.view.id, rumContext.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        DDTAssertValidRUMUUID(event.resource.id)
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
        XCTAssertEqual(try XCTUnwrap(event.action?.id.stringValue), rumContext.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.traceId, "100")
        XCTAssertEqual(event.dd.spanId, "200")
        XCTAssertEqual(event.dd.rulePsr, 0.12)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
    }

    func testGivenStartedResource_whenResourceLoadingEndsWithError_itSendsErrorEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
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
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(event.date, currentTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.view.id, rumContext.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertEqual(event.error.type, "ErrorMock")
        XCTAssertEqual(event.error.message, "network issue explanation")
        XCTAssertEqual(event.error.source, .network)
        XCTAssertEqual(event.error.stack, "network issue explanation")
        XCTAssertEqual(event.error.category, .exception)
        XCTAssertEqual(event.error.resource?.method, .post)
        XCTAssertEqual(event.error.type, "ErrorMock")
        XCTAssertNil(event.error.resource?.provider)
        XCTAssertEqual(event.error.resource?.statusCode, 500)
        XCTAssertEqual(event.error.resource?.url, "https://foo.com/resource/1")
        XCTAssertEqual(try XCTUnwrap(event.action?.id.stringValue), rumContext.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
    }

    func testGivenStartedResource_whenResourceLoadingEndsWithErrorAndFingerprintAttribute_itSendsErrorEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
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
                    attributes: [
                        "foo": "bar",
                        RUM.Attributes.errorFingerprint: "custom-fingerprint"
                    ]
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(event.date, currentTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.view.id, rumContext.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertEqual(event.error.type, "ErrorMock")
        XCTAssertEqual(event.error.message, "network issue explanation")
        XCTAssertEqual(event.error.fingerprint, "custom-fingerprint")
        XCTAssertEqual(event.error.source, .network)
        XCTAssertEqual(event.error.stack, "network issue explanation")
        XCTAssertEqual(event.error.category, .exception)
        XCTAssertEqual(event.error.resource?.method, .post)
        XCTAssertEqual(event.error.type, "ErrorMock")
        XCTAssertNil(event.error.resource?.provider)
        XCTAssertEqual(event.error.resource?.statusCode, 500)
        XCTAssertEqual(event.error.resource?.url, "https://foo.com/resource/1")
        XCTAssertEqual(try XCTUnwrap(event.action?.id.stringValue), rumContext.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
    }

    func testGivenStartedResourceInCITest_whenResourceLoadingEndsWithError_itSendsErrorEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let fakeCITestId: String = .mockRandom()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies.replacing(ciTest: .init(testExecutionId: fakeCITestId)),
            resourceKey: "/resource/1",
            startTime: currentTime,
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
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(event.date, currentTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .ciTest)
        XCTAssertEqual(event.view.id, rumContext.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertEqual(event.error.type, "ErrorMock")
        XCTAssertEqual(event.error.message, "network issue explanation")
        XCTAssertEqual(event.error.source, .network)
        XCTAssertEqual(event.error.stack, "network issue explanation")
        XCTAssertEqual(event.error.category, .exception)
        XCTAssertEqual(event.error.resource?.method, .post)
        XCTAssertEqual(event.error.type, "ErrorMock")
        XCTAssertNil(event.error.resource?.provider)
        XCTAssertEqual(event.error.resource?.statusCode, 500)
        XCTAssertEqual(event.error.resource?.url, "https://foo.com/resource/1")
        XCTAssertEqual(try XCTUnwrap(event.action?.id.stringValue), rumContext.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.ciTest?.testExecutionId, fakeCITestId)
    }

    func testGivenStartedResourceInSyntheticsTest_whenResourceLoadingEndsWithError_itSendsErrorEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let fakeSyntheticsTestId: String = .mockRandom()
        let fakeSyntheticsResultId: String = .mockRandom()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies.replacing(syntheticsTest: .init(injected: nil, resultId: fakeSyntheticsResultId, testId: fakeSyntheticsTestId)),
            resourceKey: "/resource/1",
            startTime: currentTime,
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
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(event.date, currentTime.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .synthetics)
        XCTAssertEqual(event.view.id, rumContext.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertEqual(event.error.type, "ErrorMock")
        XCTAssertEqual(event.error.message, "network issue explanation")
        XCTAssertEqual(event.error.source, .network)
        XCTAssertEqual(event.error.stack, "network issue explanation")
        XCTAssertEqual(event.error.category, .exception)
        XCTAssertEqual(event.error.resource?.method, .post)
        XCTAssertEqual(event.error.type, "ErrorMock")
        XCTAssertNil(event.error.resource?.provider)
        XCTAssertEqual(event.error.resource?.statusCode, 500)
        XCTAssertEqual(event.error.resource?.url, "https://foo.com/resource/1")
        XCTAssertEqual(try XCTUnwrap(event.action?.id.stringValue), rumContext.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.synthetics?.testId, fakeSyntheticsTestId)
        XCTAssertEqual(event.synthetics?.resultId, fakeSyntheticsResultId)
    }

    func testGivenConfiguredSource_whenResourceLoadingEndsWithError_itSendsErrorEventWithConfiguredSource() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        let source = String.mockAnySource()
        let customContext: DatadogContext = .mockWith(
            service: "test-service",
            source: source
        )

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
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
                ),
                context: customContext,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(event.source, .init(rawValue: source))
        XCTAssertEqual(event.service, "test-service")
    }

    func testGivenStartedResource_whenResourceReceivesMetricsBeforeItEnds_itUsesMetricValuesInSentResourceEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
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

        XCTAssertTrue(scope.process(command: metricsCommand, context: context, writer: writer))

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
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let metrics = metricsCommand.metrics
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.date, metrics.fetch.start.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.view.id, rumContext.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        DDTAssertValidRUMUUID(event.resource.id)
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
        XCTAssertEqual(try XCTUnwrap(event.action?.id.stringValue), rumContext.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
    }

    func testGivenMultipleResourceScopes_whenSendingResourceEvents_eachEventHasUniqueResourceID() throws {
        let resourceKey: String = .mockAny()
        func createScope(url: String) -> RUMResourceScope {
            RUMResourceScope.mockWith(
                context: rumContext,
                dependencies: dependencies,
                resourceKey: resourceKey,
                url: url
            )
        }

        let scope1 = createScope(url: "/r/1")
        let scope2 = createScope(url: "/r/2")

        // When
        _ = scope1.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey),
            context: context,
            writer: writer
        )
        _ = scope2.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey),
            context: context,
            writer: writer
        )

        // Then
        let resourceEvents = writer.events(ofType: RUMResourceEvent.self)
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
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: Date(),
            httpMethod: .post,
            resourceKindBasedOnRequest: kindBasedOnRequest
        )

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand.mockWith(
                    resourceKey: "/resource/1",
                    kind: kindBasedOnResponse
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(event.resource.type, kindBasedOnRequest)
    }

    func testGivenStartedFirstPartyResource_whenResourceLoadingEnds_itSendsResourceEventWithFirstPartyProvider() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://firstparty.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: true
        )

        currentTime.addTimeInterval(2)

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        let providerType = try XCTUnwrap(event.resource.provider?.type)
        let providerDomain = try XCTUnwrap(event.resource.provider?.domain)
        XCTAssertEqual(providerType, .firstParty)
        XCTAssertEqual(providerDomain, "firstparty.com")
    }

    func testGivenStartedThirdartyResource_whenResourceLoadingEnds_itSendsResourceEventWithoutResourceProvider() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: false
        )

        currentTime.addTimeInterval(2)

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).first)
        XCTAssertNil(event.resource.provider)
    }

    func testGivenStartedFirstPartyResource_whenResourceLoadingEndsWithError_itSendsErrorEventWithFirstPartyProvider() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://firstparty.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: true
        )

        currentTime.addTimeInterval(2)

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).first)
        let providerType = try XCTUnwrap(event.error.resource?.provider?.type)
        let providerDomain = try XCTUnwrap(event.error.resource?.provider?.domain)
        XCTAssertEqual(providerType, .firstParty)
        XCTAssertEqual(providerDomain, "firstparty.com")
        XCTAssertEqual(event.error.sourceType, .ios)
    }

    func testGivenStartedThirdPartyResource_whenResourceLoadingEndsWithError_itSendsErrorEventWithoutResourceProvider() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            isFirstPartyResource: false
        )

        currentTime.addTimeInterval(2)

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).first)
        XCTAssertNil(event.error.resource?.provider)
        XCTAssertEqual(event.error.sourceType, .ios)
    }

    func testGivenStartedResource_whenResourceLoadingEndsWithErrorWithCustomSourceType_itSendsErrorEventWithCustomSourceType() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let resourceKey = "/resource/1"
        // Given
        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: resourceKey,
            startTime: currentTime,
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
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(event.error.sourceType, .reactNative)
    }

    func testGivenStartedResource_whenResourceLoadingEndsWithError_itSendsErrorEventWithTimeSinceAppStart() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()

        // Given
        let appLauchToErrorTimeDiff = Int64.random(in: 10..<1_000_000)
        let customContext: DatadogContext = .mockWith(launchTime: .mockWith(
            launchTime: .mockAny(),
            launchDate: currentTime,
            isActivePrewarm: .mockAny()
        ) )

        let scope = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post
        )

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(
                    resourceKey: "/resource/1",
                    time: currentTime.addingTimeInterval(Double(appLauchToErrorTimeDiff))
                ),
                context: customContext,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(event.error.timeSinceAppStart, appLauchToErrorTimeDiff * 1_000)
    }

    // MARK: - Events sending callbacks

    func testGivenResourceScopeWithDefaultEventsMapper_whenSendingEvents_thenEventSentCallbacksAreCalled() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        var onResourceEventCalled = false
        var onErrorEventCalled = false
        // Given
        let scope1 = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            onResourceEvent: { onResourceEventCalled = $0 }
        )

        let scope2 = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/2",
            startTime: currentTime,
            url: "https://foo.com/resource/2",
            httpMethod: .post,
            onErrorEvent: { onErrorEventCalled = $0 }
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
                ),
                context: context,
                writer: writer
            )
        )

        XCTAssertFalse(
            scope2.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            )
        )

        // Then
        XCTAssertFalse(writer.events(ofType: RUMResourceEvent.self).isEmpty)
        XCTAssertTrue(onResourceEventCalled)
        XCTAssertTrue(onErrorEventCalled)
    }

    func testGivenResourceScopeWithDroppingEventsMapper_whenBypassingSendingEvents_thenEventSentCallbacksAreNotCalled() {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        var onResourceEventCalled = false
        var onErrorEventCalled = false

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
        let dependencies: RUMScopeDependencies = .mockWith(
            eventBuilder: eventBuilder
        )

        // swiftlint:disable trailing_closure
        let scope1 = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/1",
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: .post,
            onResourceEvent: { onResourceEventCalled = $0 }
        )

        let scope2 = RUMResourceScope.mockWith(
            context: rumContext,
            dependencies: dependencies,
            resourceKey: "/resource/2",
            startTime: currentTime,
            url: "https://foo.com/resource/2",
            httpMethod: .post,
            onErrorEvent: { onErrorEventCalled = $0 }
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
                ),
                context: context,
                writer: writer
            )
        )

        XCTAssertFalse(
            scope2.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            )
        )

        // Then
        XCTAssertTrue(writer.events(ofType: RUMResourceEvent.self).isEmpty)
        XCTAssertFalse(onResourceEventCalled)
        XCTAssertFalse(onErrorEventCalled)
    }

    // MARK: - Updating Time To Network Settled Metric

    func testWhenResourceLoadingEnds_itTrackStartAndStopInTTNSMetric() throws {
        let resourceKey = "resource"
        let resourceDuration: TimeInterval = 2
        let viewStartDate = Date()
        let resourceUUID = RUMUUID(rawValue: UUID())

        // Given
        let metric = TTNSMetricMock()
        let scope = RUMResourceScope(
            context: .mockAny(),
            dependencies: .mockWith(
                rumUUIDGenerator: RUMUUIDGeneratorMock(uuid: resourceUUID)
            ),
            resourceKey: resourceKey,
            attributes: [:],
            startTime: viewStartDate,
            serverTimeOffset: .mockRandom(),
            url: .mockAny(),
            httpMethod: .mockAny(),
            resourceKindBasedOnRequest: nil,
            spanContext: nil,
            networkSettledMetric: metric,
            onResourceEvent: { _ in },
            onErrorEvent: { _ in }
        )

        // When
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: viewStartDate + resourceDuration
            ),
            context: .mockAny(),
            writer: writer
        )

        // Then
        XCTAssertEqual(metric.resourceStartDates[resourceUUID], viewStartDate)
        XCTAssertEqual(metric.resourceEndDates[resourceUUID]?.0, viewStartDate + resourceDuration)
        XCTAssertEqual(metric.resourceEndDates[resourceUUID]?.1, resourceDuration)
    }

    func testWhenResourceLoadingEndsWithError_thenItsDurationTrackedInTTNSMetric() throws {
        let resourceKey = "resource"
        let resourceDuration: TimeInterval = 2
        let viewStartDate = Date()
        let resourceUUID = RUMUUID(rawValue: UUID())

        // Given
        let metric = TTNSMetricMock()
        let scope = RUMResourceScope(
            context: .mockAny(),
            dependencies: .mockWith(
                rumUUIDGenerator: RUMUUIDGeneratorMock(uuid: resourceUUID)
            ),
            resourceKey: resourceKey,
            attributes: [:],
            startTime: viewStartDate,
            serverTimeOffset: .mockRandom(),
            url: .mockAny(),
            httpMethod: .mockAny(),
            resourceKindBasedOnRequest: nil,
            spanContext: nil,
            networkSettledMetric: metric,
            onResourceEvent: { _ in },
            onErrorEvent: { _ in }
        )

        // When
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(
                resourceKey: resourceKey,
                time: viewStartDate + resourceDuration
            ),
            context: .mockAny(),
            writer: writer
        )

        // Then
        XCTAssertEqual(metric.resourceStartDates[resourceUUID], viewStartDate)
        XCTAssertEqual(metric.resourceEndDates[resourceUUID]?.0, viewStartDate + resourceDuration)
        XCTAssertNil(metric.resourceEndDates[resourceUUID]?.1)
    }

    func testWhenResourceLoadingEndsAndResourceIsDropped_itTrackStoppedInTTNSMetric() throws {
        let resourceKey = "resource"
        let viewStartDate = Date()
        let resourceUUID = RUMUUID(rawValue: UUID())

        // Given
        let metric = TTNSMetricMock()
        let scope = RUMResourceScope(
            context: .mockAny(),
            dependencies: .mockWith(
                eventBuilder: RUMEventBuilder(
                    eventsMapper: .mockWith(
                        errorEventMapper: { _ in return nil }, // drop ALL errors
                        resourceEventMapper: { _ in return nil } // drop ALL resources
                    )
                ),
                rumUUIDGenerator: RUMUUIDGeneratorMock(uuid: resourceUUID)
            ),
            resourceKey: resourceKey,
            attributes: [:],
            startTime: viewStartDate,
            serverTimeOffset: .mockRandom(),
            url: .mockAny(),
            httpMethod: .mockAny(),
            resourceKindBasedOnRequest: nil,
            spanContext: nil,
            networkSettledMetric: metric,
            onResourceEvent: { _ in },
            onErrorEvent: { _ in }
        )

        // When (end with completion or error)
        oneOf([
            {
                _ = scope.process(
                    command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey, time: viewStartDate + 1),
                    context: .mockAny(),
                    writer: self.writer
                )
            },
            {
                _ = scope.process(
                    command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: resourceKey, time: viewStartDate + 1),
                    context: .mockAny(),
                    writer: self.writer
                )
            }
        ])

        // Then
        XCTAssertEqual(metric.resourcesDropped, [resourceUUID])
    }
}
