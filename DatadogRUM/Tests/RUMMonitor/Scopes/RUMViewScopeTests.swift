/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

class RUMViewScopeTests: XCTestCase {
    var context: DatadogContext = .mockWith(
        service: "test-service",
        version: "test-version",
        buildNumber: "test-build",
        buildId: .mockRandom(),
        device: .mockWith(name: "device-name", logicalCpuCount: 4, totalRam: 2_048),
        os: .mockWith(
            name: "device-os",
            version: "os-version",
            build: "os-build"
        ),
        networkConnectionInfo: nil,
        carrierInfo: nil
    )

    let writer = FileWriterMock()

    private let parent = RUMContextProviderMock()

    func testDefaultContext() {
        let applicationScope = RUMApplicationScope(
            dependencies: .mockWith(rumApplicationID: "rum-123")
        )

        let sessionScope: RUMSessionScope = .mockWith(parent: applicationScope)

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: sessionScope,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockRandom(),
            name: .mockRandom(),
            customTimings: [:],
            startTime: .mockAny(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, sessionScope.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, scope.viewUUID)
        XCTAssertEqual(scope.context.activeViewPath, scope.viewPath)
        XCTAssertEqual(scope.context.activeViewName, scope.viewName)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testContextWhenViewHasAnActiveUserAction() {
        let applicationScope = RUMApplicationScope(
            dependencies: .mockWith(rumApplicationID: "rum-123")
        )
        let sessionScope: RUMSessionScope = .mockWith(parent: applicationScope)

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: sessionScope,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockRandom(),
            name: .mockRandom(),
            customTimings: [:],
            startTime: .mockAny(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        _ = scope.process(
            command: RUMStartUserActionCommand.mockAny(),
            context: context,
            writer: writer
        )

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, sessionScope.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, scope.viewUUID)
        XCTAssertEqual(scope.context.activeViewPath, scope.viewPath)
        XCTAssertEqual(scope.context.activeViewName, scope.viewName)
        XCTAssertEqual(scope.context.activeUserActionID, try XCTUnwrap(scope.userActionScope?.actionUUID))
    }

    func testWhenInitialViewReceivesAnyCommand_itSendsViewUpdateEvent() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: .mockWith(
                networkSettledMetricFactory: { _, _ in TNSMetricMock(value: .success(0.42)) }
            ),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(mockedValue: .success(0.84)),
            viewIndexInSession: .mockAny()
        )

        let hasReplay: Bool = .mockRandom()
        let traceSampleRate: SampleRate = .mockRandom(min: 0, max: 100)
        let sessionReplaySampleRate: SampleRate = .mockRandom(min: 0, max: 100)
        let startRecordingManually: Bool = .random()
        var context = self.context
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: hasReplay))
        context.set(additionalContext: SessionReplayCoreContext.RecordsCount(value: [scope.viewUUID.toRUMDataFormat: 1]))
        context.set(additionalContext: TraceCoreContext.Configuration(sampleRate: traceSampleRate))
        context.set(additionalContext: SessionReplayCoreContext.Configuration(
            sampleRate: sessionReplaySampleRate,
            startRecordingManually: startRecordingManually
        ))

        _ = scope.process(
            command: RUMCommandMock(time: currentTime),
            context: context,
            writer: writer
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.session.hasReplay, hasReplay)
        DDTAssertValidRUMUUID(event.view.id)
        XCTAssertEqual(event.view.url, "UIViewController")
        XCTAssertEqual(event.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.view.isActive)
        XCTAssertTrue(viewIsActive)
        XCTAssertEqual(event.view.timeSpent, 1) // Minimum `time_spent of 1 nanosecond
        XCTAssertEqual(event.view.action.count, 0)
        XCTAssertEqual(event.view.error.count, 0)
        XCTAssertEqual(event.view.resource.count, 0)
        XCTAssertEqual(event.view.networkSettledTime, 420_000_000)
        XCTAssertEqual(event.view.interactionToNextViewTime, 840_000_000)
        XCTAssertEqual(event.dd.documentVersion, 1)
        XCTAssertEqual(event.dd.configuration?.traceSampleRate, Double(traceSampleRate))
        XCTAssertEqual(event.dd.configuration?.sessionReplaySampleRate, Double(sessionReplaySampleRate))
        XCTAssertEqual(event.dd.configuration?.startSessionReplayRecordingManually, startRecordingManually)
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.device?.logicalCpuCount, 4)
        XCTAssertEqual(event.device?.totalRam, 2_048)
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.os?.version, "os-version")
        XCTAssertEqual(event.os?.build, "os-build")
        XCTAssertEqual(event.dd.replayStats?.recordsCount, 1)
    }

    func testWhenInitialViewHasConfiguredSource_itSendsViewUpdateEventWithConfiguredSource() throws {
        // GIVEN
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let source = String.mockAnySource()

        let customContext: DatadogContext = .mockWith(source: source)

        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        _ = scope.process(
            command: RUMCommandMock(time: currentTime),
            context: customContext,
            writer: writer
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(event.source, .init(rawValue: source))
    }

    func testWhenViewIsStarted_itSendsViewUpdateEvent() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let isInitialView: Bool = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: isInitialView,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    time: currentTime,
                    attributes: ["foo": "bar 2", "fizz": "buzz"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        DDTAssertValidRUMUUID(event.view.id)
        XCTAssertEqual(event.view.url, "UIViewController")
        XCTAssertEqual(event.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.view.isActive)
        XCTAssertTrue(viewIsActive)
        XCTAssertEqual(event.view.timeSpent, 1) // Minimum `time_spent of 1 nanosecond
        XCTAssertEqual(event.view.action.count, 0)
        XCTAssertEqual(event.view.error.count, 0)
        XCTAssertEqual(event.view.resource.count, 0)
        XCTAssertEqual(event.dd.documentVersion, 1)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar 2", "fizz": "buzz"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.device?.logicalCpuCount, 4)
        XCTAssertEqual(event.device?.totalRam, 2_048)
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.os?.version, "os-version")
        XCTAssertEqual(event.os?.build, "os-build")
    }

    func testWhenViewIsStopped_itSendsViewUpdateEvent_andEndsTheScope() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let isInitialView: Bool = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: isInitialView,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    time: currentTime,
                    attributes: ["foo": "bar"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )
        currentTime.addTimeInterval(2)
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            ),
            "The scope should end."
        )

        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 2)
        viewEvents.forEach { viewEvent in
            XCTAssertEqual(
                viewEvent.date,
                Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds,
                "All View events must share the same creation date"
            )
        }

        let event = try XCTUnwrap(viewEvents.dropFirst().first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        DDTAssertValidRUMUUID(event.view.id)
        XCTAssertEqual(event.view.url, "UIViewController")
        XCTAssertEqual(event.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.view.isActive)
        XCTAssertFalse(viewIsActive)
        XCTAssertEqual(event.view.timeSpent, TimeInterval(2).dd.toInt64Nanoseconds)
        XCTAssertEqual(event.view.action.count, 0)
        XCTAssertEqual(event.view.error.count, 0)
        XCTAssertEqual(event.view.resource.count, 0)
        XCTAssertEqual(event.dd.documentVersion, 2)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.device?.logicalCpuCount, 4)
        XCTAssertEqual(event.device?.totalRam, 2_048)
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.os?.version, "os-version")
        XCTAssertEqual(event.os?.build, "os-build")
    }

    func testWhenViewIsStopped_itMakesAttributesImmutable() throws {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let isInitialView: Bool = .mockRandom()
        let initialAttributes = ["key1": "value1", "key2": "value2"]
        let scope = RUMViewScope(
            isInitialView: isInitialView,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    time: currentTime,
                    attributes: initialAttributes,
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )
        currentTime.addTimeInterval(1)
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            ),
            "The scope should end."
        )

        // Send a new command after view is stopped with additional attributes
        XCTAssertFalse(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(attributes: ["additionalFoo": "additionalBar"]),
                context: context,
                writer: writer
            ),
            "The command should be ignored."
        )

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 2)
        viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.context?.contextInfo as? [String: String], initialAttributes)
        }
    }

    func testWhenViewIsStoppedInCITest_itSendsViewUpdateEvent_andEndsTheScope() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let isInitialView: Bool = .mockRandom()
        let fakeCiTestId: String = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: isInitialView,
            parent: parent,
            dependencies: .mockWith(ciTest: .init(testExecutionId: fakeCiTestId)),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    time: currentTime,
                    attributes: ["foo": "bar"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )
        currentTime.addTimeInterval(2)
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            ),
            "The scope should end."
        )

        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 2)
        viewEvents.forEach { viewEvent in
            XCTAssertEqual(
                viewEvent.date,
                Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds,
                "All View events must share the same creation date"
            )
        }

        let event = try XCTUnwrap(viewEvents.dropFirst().first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .ciTest)
        DDTAssertValidRUMUUID(event.view.id)
        XCTAssertEqual(event.view.url, "UIViewController")
        XCTAssertEqual(event.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.view.isActive)
        XCTAssertFalse(viewIsActive)
        XCTAssertEqual(event.view.timeSpent, TimeInterval(2).dd.toInt64Nanoseconds)
        XCTAssertEqual(event.view.action.count, 0)
        XCTAssertEqual(event.view.error.count, 0)
        XCTAssertEqual(event.view.resource.count, 0)
        XCTAssertEqual(event.dd.documentVersion, 2)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.device?.logicalCpuCount, 4)
        XCTAssertEqual(event.device?.totalRam, 2_048)
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.os?.version, "os-version")
        XCTAssertEqual(event.os?.build, "os-build")
        XCTAssertEqual(event.ciTest?.testExecutionId, fakeCiTestId)
    }

    func testWhenViewIsStoppedInSyntheticsTest_itSendsViewUpdateEvent_andEndsTheScope() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let isInitialView: Bool = .mockRandom()
        let fakeSyntheticsTestId: String = .mockRandom()
        let fakeSyntheticsResultId: String = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: isInitialView,
            parent: parent,
            dependencies: .mockWith(syntheticsTest: .init(injected: nil, resultId: fakeSyntheticsResultId, testId: fakeSyntheticsTestId)),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    time: currentTime,
                    attributes: ["foo": "bar"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )
        currentTime.addTimeInterval(2)
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            ),
            "The scope should end."
        )

        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 2)
        viewEvents.forEach { viewEvent in
            XCTAssertEqual(
                viewEvent.date,
                Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds,
                "All View events must share the same creation date"
            )
        }

        let event = try XCTUnwrap(viewEvents.dropFirst().first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .synthetics)
        DDTAssertValidRUMUUID(event.view.id)
        XCTAssertEqual(event.view.url, "UIViewController")
        XCTAssertEqual(event.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.view.isActive)
        XCTAssertFalse(viewIsActive)
        XCTAssertEqual(event.view.timeSpent, TimeInterval(2).dd.toInt64Nanoseconds)
        XCTAssertEqual(event.view.action.count, 0)
        XCTAssertEqual(event.view.error.count, 0)
        XCTAssertEqual(event.view.resource.count, 0)
        XCTAssertEqual(event.dd.documentVersion, 2)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.device?.logicalCpuCount, 4)
        XCTAssertEqual(event.device?.totalRam, 2_048)
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.os?.version, "os-version")
        XCTAssertEqual(event.os?.build, "os-build")
        XCTAssertEqual(event.synthetics?.testId, fakeSyntheticsTestId)
        XCTAssertEqual(event.synthetics?.resultId, fakeSyntheticsResultId)
    }

    func testWhenViewStartWithSessionTypeOverride() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let isInitialView: Bool = .mockRandom()
        let fakeSyntheticsTestId: String = .mockRandom()
        let fakeSyntheticsResultId: String = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: isInitialView,
            parent: parent,
            dependencies: .mockWith(
                syntheticsTest: .init(injected: nil, resultId: fakeSyntheticsResultId, testId: fakeSyntheticsTestId),
                sessionType: .user
            ),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    time: currentTime,
                    attributes: ["foo": "bar"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )

        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 1)

        let event = try XCTUnwrap(viewEvents.first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        DDTAssertValidRUMUUID(event.view.id)
        XCTAssertEqual(event.view.url, "UIViewController")
        XCTAssertEqual(event.view.name, "ViewName")
        XCTAssertEqual(event.view.action.count, 0)
        XCTAssertEqual(event.view.error.count, 0)
        XCTAssertEqual(event.view.resource.count, 0)
        XCTAssertEqual(event.dd.documentVersion, 1)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.device?.logicalCpuCount, 4)
        XCTAssertEqual(event.device?.totalRam, 2_048)
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.os?.version, "os-version")
        XCTAssertEqual(event.os?.build, "os-build")
        XCTAssertEqual(event.synthetics?.testId, fakeSyntheticsTestId)
        XCTAssertEqual(event.synthetics?.resultId, fakeSyntheticsResultId)
    }

    func testWhenAnotherViewIsStarted_itEndsTheScope() throws {
        let view1 = createMockView(viewControllerClassName: "FirstViewController")
        let view2 = createMockView(viewControllerClassName: "SecondViewController")
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: ViewIdentifier(view1),
            path: "FirstViewController",
            name: "FirstViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
             scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: ViewIdentifier(view1)),
                context: context,
                writer: writer
             )
         )

        currentTime.addTimeInterval(1)

        XCTAssertFalse(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: ViewIdentifier(view2)),
                context: context,
                writer: writer
            ),
            "The scope should end as another View is started."
        )

        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 2)
        let view1WasActive = try XCTUnwrap(viewEvents[0].view.isActive)
        XCTAssertTrue(view1WasActive)
        XCTAssertEqual(viewEvents[1].view.url, "FirstViewController")
        XCTAssertEqual(viewEvents[1].view.name, "FirstViewName")
        let view2IsActive = try XCTUnwrap(viewEvents[1].view.isActive)
        XCTAssertFalse(view2IsActive)
        XCTAssertEqual(viewEvents[1].view.timeSpent, TimeInterval(1).dd.toInt64Nanoseconds, "The View should last for 1 second")
    }

    func testWhenTheViewIsStartedAnotherTime_itEndsTheScope() throws {
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "FirstViewController",
            name: "FirstViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            ),
            "The scope should be kept as the View was started for the first time."
        )
        XCTAssertFalse(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            ),
            "The scope should end as the View was started for another time."
        )

        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 2)
        let viewWasActive = try XCTUnwrap(viewEvents[0].view.isActive)
        XCTAssertTrue(viewWasActive)
        XCTAssertEqual(viewEvents[0].view.url, "FirstViewController")
        XCTAssertEqual(viewEvents[0].view.name, "FirstViewName")
        let viewIsActive = try XCTUnwrap(viewEvents[1].view.isActive)
        XCTAssertFalse(viewIsActive)
        XCTAssertEqual(viewEvents[0].view.timeSpent, TimeInterval(1).dd.toInt64Nanoseconds, "The View should last for 1 second")
    }

    func testGivenMultipleViewScopes_whenSendingViewEvent_eachScopeUsesUniqueViewID() throws {
        func createScope(uri: String, name: String) -> RUMViewScope {
            RUMViewScope(
                isInitialView: false,
                parent: parent,
                dependencies: .mockAny(),
                identity: .mockViewIdentifier(),
                path: uri,
                name: name,
                customTimings: [:],
                startTime: .mockAny(),
                serverTimeOffset: .zero,
                interactionToNextViewMetric: INVMetricMock(),
                viewIndexInSession: .mockAny()
            )
        }

        // Given
        let scope1 = createScope(uri: "View1URL", name: "View1Name")
        let scope2 = createScope(uri: "View2URL", name: "View2Name")

        // When
        [scope1, scope2].forEach { scope in
            _ = scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
            _ = scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        }

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        let view1Events = viewEvents.filter { $0.view.url == "View1URL" && $0.view.name == "View1Name" }
        let view2Events = viewEvents.filter { $0.view.url == "View2URL" && $0.view.name == "View2Name" }
        XCTAssertEqual(view1Events.count, 2)
        XCTAssertEqual(view2Events.count, 2)
        XCTAssertEqual(view1Events[0].view.id, view1Events[1].view.id)
        XCTAssertEqual(view2Events[0].view.id, view2Events[1].view.id)
        XCTAssertNotEqual(view1Events[0].view.id, view2Events[0].view.id)
    }

    func testWhenEventsAreSent_theyIncludeSessionPrecondition() throws {
        let processLaunchDate: Date = .mockDecember15th2019At10AMUTC()
        var currentTime = processLaunchDate
        context.applicationStateHistory = .mockWith(initialState: .inactive, date: .distantPast)
        context.launchInfo = .mockWith(processLaunchDate: processLaunchDate)
        let randomPrecondition: RUMSessionPrecondition = .mockRandom()
        parent.context.sessionPrecondition = randomPrecondition

        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: processLaunchDate,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(command: RUMApplicationStartCommand.mockWith(time: currentTime), context: context, writer: writer)

        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .custom), context: context, writer: writer)

        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime, message: .mockAny()), context: context, writer: writer)

        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMAddLongTaskCommand.mockWith(time: currentTime), context: context, writer: writer)

        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMStartResourceCommand.mockWith(resourceKey: "key", time: currentTime), context: context, writer: writer)

        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMStopResourceCommand.mockWith(resourceKey: "key", time: currentTime), context: context, writer: writer)

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertGreaterThan(viewEvents.count, 1)
        viewEvents.forEach { XCTAssertEqual($0.dd.session?.sessionPrecondition, randomPrecondition) }

        let actionEvents = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actionEvents.count, 1)
        actionEvents.forEach { XCTAssertEqual($0.dd.session?.sessionPrecondition, randomPrecondition) }

        let errorEvents = writer.events(ofType: RUMErrorEvent.self)
        XCTAssertGreaterThan(errorEvents.count, 0)
        errorEvents.forEach { XCTAssertEqual($0.dd.session?.sessionPrecondition, randomPrecondition) }

        let longTaskEvents = writer.events(ofType: RUMLongTaskEvent.self)
        XCTAssertGreaterThan(longTaskEvents.count, 0)
        longTaskEvents.forEach { XCTAssertEqual($0.dd.session?.sessionPrecondition, randomPrecondition) }

        let resourceEvents = writer.events(ofType: RUMResourceEvent.self)
        XCTAssertGreaterThan(resourceEvents.count, 0)
        resourceEvents.forEach { XCTAssertEqual($0.dd.session?.sessionPrecondition, randomPrecondition) }
    }

    // MARK: - View Attributes

    func testWhenViewAttributesAreSet_nextEventsHaveThem() throws {
        let scope: RUMViewScope = .mockWith(parent: parent)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    attributes: ["viewKey": "viewValue"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        var event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["viewKey": "viewValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["viewKey": "viewValue"])

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewAttributesCommand.mockWith(
                    attributes: ["newViewKey": "newViewValue"]
                ),
                context: context,
                writer: writer
            )
        )
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(
                    attributes: ["anotherKey": "anotherValue"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["viewKey": "viewValue", "newViewKey": "newViewValue", "anotherKey": "anotherValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["viewKey": "viewValue", "newViewKey": "newViewValue", "anotherKey": "anotherValue"])
    }

    func testWhenViewAttributesAreRemoved_eventsDoNotIncludeThem() throws {
        let scope: RUMViewScope = .mockWith(parent: parent)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    attributes: ["viewKey": "viewValue"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        var event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["viewKey": "viewValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["viewKey": "viewValue"])

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMRemoveViewAttributesCommand.mockWith(
                    keysToRemove: ["viewKey"]
                ),
                context: context,
                writer: writer
            )
        )
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(),
                context: context,
                writer: writer
            )
        )

        // Then
        event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, [:])
        DDAssertDictionariesEqual(event.context!.contextInfo, [:])
    }

    func testWhenInternalViewAttributesAreSet_eventsAreNotAffected() throws {
        let scope: RUMViewScope = .mockWith(parent: parent)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    attributes: ["viewKey": "viewValue"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMAddViewAttributesCommand.mockWith(
                    attributes: ["internalKey": "internalValue"],
                    areInternalAttributes: true
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        var event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["viewKey": "viewValue"])
        DDAssertDictionariesEqual(scope.internalAttributes, ["internalKey": "internalValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["viewKey": "viewValue"])

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(
                    attributes: ["viewKey": "newViewValue"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )
        // Then
        event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["viewKey": "newViewValue"])
        DDAssertDictionariesEqual(scope.internalAttributes, ["internalKey": "internalValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["viewKey": "newViewValue"])
    }

    // Attributes on views are immediately propagated to their child events after they are added.
    func testWhenViewAttributesAreSet_childEventsHaveThem() throws {
        let scope: RUMViewScope = .mockWith(parent: parent)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    globalAttributes: [:],
                    attributes: ["viewKey": "viewValue"]
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        var viewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["viewKey": "viewValue"])
        DDAssertDictionariesEqual(viewEvent.context!.contextInfo, ["viewKey": "viewValue"])

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockWith(
                    globalAttributes: ["globalKey": "globalValue"],
                    attributes: ["localKey": "localValue"],
                    actionType: .custom
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        viewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        let actionEvent = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertNil(scope.userActionScope, "It should not count custom action as pending")
        DDAssertDictionariesEqual(scope.attributes, ["viewKey": "viewValue"])
        DDAssertDictionariesEqual(viewEvent.context!.contextInfo, ["viewKey": "viewValue", "globalKey": "globalValue"])
        DDAssertDictionariesEqual(actionEvent.context!.contextInfo, ["viewKey": "viewValue", "globalKey": "globalValue", "localKey": "localValue"])

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewAttributesCommand.mockWith(
                    attributes: ["newViewKey": "newViewValue"]
                ),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockAny(),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(
                    globalAttributes: ["globalKey": "globalValue"],
                    attributes: ["resourceKey": "resourceValue"]
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        viewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        let resourceEvent = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["viewKey": "viewValue", "newViewKey": "newViewValue"])
        DDAssertDictionariesEqual(viewEvent.context!.contextInfo, ["viewKey": "viewValue", "newViewKey": "newViewValue", "globalKey": "globalValue"])
        DDAssertDictionariesEqual(
            resourceEvent.context!.contextInfo,
            [
                "resourceKey": "resourceValue",
                "viewKey": "viewValue",
                "newViewKey": "newViewValue",
                "globalKey": "globalValue"
            ]
        )
    }

    // Attributes are overwritten in events as they become more specific, so the precedence order is “Local, View, Global”.
    func testWhenViewAttributesCollide_thePrecedenceIsRespected() throws {
        let scope: RUMViewScope = .mockWith(parent: parent)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    globalAttributes: ["key": "globalValue"],
                    attributes: ["key": "viewValue"]
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        var viewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "viewValue"])
        DDAssertDictionariesEqual(viewEvent.context!.contextInfo, ["key": "viewValue"])

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockWith(
                    globalAttributes: ["key": "globalValue"],
                    attributes: ["key": "localValue"],
                    actionType: .custom
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        viewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        let actionEvent = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "viewValue"])
        DDAssertDictionariesEqual(viewEvent.context!.contextInfo, ["key": "viewValue"])
        DDAssertDictionariesEqual(actionEvent.context!.contextInfo, ["key": "localValue"])

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockAny(),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(
                    globalAttributes: ["key": "globalValue"],
                    attributes: ["key": "resourceValue"]
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        viewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        let resourceEvent = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "viewValue"])
        DDAssertDictionariesEqual(viewEvent.context!.contextInfo, ["key": "viewValue"])
        DDAssertDictionariesEqual(resourceEvent.context!.contextInfo, ["key": "resourceValue"])
    }

    // View attributes are not added or overwritten after a view has “stopped”, even if that view is still active because of Resource or Action events.
    // Changes to global attributes also do not affect “stopped” views, but should be transferred to other active events when they are stopped.
    func testWhenViewAttributesChangeOnStoppedViewWithActiveResources() throws {
        let view1 = "view1"
        let view2 = "view2"
        let firstViewScope: RUMViewScope = .mockWith(parent: parent, identity: ViewIdentifier(view1), name: view1)

        // When
        XCTAssertTrue(
            firstViewScope.process(
                command: RUMStartViewCommand.mockWith(
                    globalAttributes: ["globalKey": "globalValue"],
                    attributes: ["viewKey": "viewValue"],
                    identity: ViewIdentifier(view1),
                    name: "view1"
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        var view1Event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(firstViewScope.attributes, ["viewKey": "viewValue"])
        DDAssertDictionariesEqual(view1Event.context!.contextInfo, ["viewKey": "viewValue", "globalKey": "globalValue"])

        // When
        XCTAssertTrue(
            firstViewScope.process(
                command: RUMStartResourceCommand.mockWith(
                    globalAttributes: ["globalKey": "globalValue"],
                    attributes: ["resourceKey": "resourceValue"]
                ),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            firstViewScope.process(
                command: RUMAddViewAttributesCommand.mockWith(
                    attributes: ["newViewKey": "newViewValue"]
                ),
                context: context,
                writer: writer
            )
        )

        let startView2Command = RUMStartViewCommand.mockWith(
            globalAttributes: ["globalKey": "globalValue"],
            attributes: ["view2Key": "view2Value"],
            identity: ViewIdentifier(view2),
            name: view2
        )
        XCTAssertTrue(firstViewScope.process(command: startView2Command, context: context, writer: writer))
        let secondViewScope: RUMViewScope = .mockWith(parent: parent, identity: ViewIdentifier(view2), name: view2)
        XCTAssertTrue(secondViewScope.process(command: startView2Command, context: context, writer: writer))

        // Then
        view1Event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last(where: { $0.view.name == "view1" }))
        let view2Event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last(where: { $0.view.name == "view2" }))
        // First view scope is inactive with the final snapshot of attributes
        DDAssertDictionariesEqual(firstViewScope.attributes, ["viewKey": "viewValue", "newViewKey": "newViewValue", "globalKey": "globalValue"])
        DDAssertDictionariesEqual(secondViewScope.attributes, ["view2Key": "view2Value"])
        DDAssertDictionariesEqual(view1Event.context!.contextInfo, ["viewKey": "viewValue", "newViewKey": "newViewValue", "globalKey": "globalValue"])
        DDAssertDictionariesEqual(view2Event.context!.contextInfo, ["view2Key": "view2Value", "globalKey": "globalValue"])

        // When
        XCTAssertTrue(
            secondViewScope.process(
                command: RUMAddViewAttributesCommand.mockWith(
                    attributes: ["newView2Key": "newView2Value"]
                ),
                context: context,
                writer: writer
            )
        )

        XCTAssertFalse(
            firstViewScope.process(
                command: RUMStopResourceCommand.mockWith(
                    globalAttributes: ["globalKey": "globalValue", "newGlobalKey": "newGlobalValue"],
                    attributes: [:]
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        view1Event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        let resourceEvent = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).last)
        // First view scope is inactive with the final snapshot of attributes
        DDAssertDictionariesEqual(firstViewScope.attributes, ["viewKey": "viewValue", "newViewKey": "newViewValue", "globalKey": "globalValue"])
        DDAssertDictionariesEqual(secondViewScope.attributes, ["view2Key": "view2Value", "newView2Key": "newView2Value"])
        DDAssertDictionariesEqual(
            view1Event.context!.contextInfo,
            [
                "viewKey": "viewValue",
                "newViewKey": "newViewValue",
                "globalKey": "globalValue"
            ]
        )
        DDAssertDictionariesEqual(
            resourceEvent.context!.contextInfo,
            [
                "resourceKey": "resourceValue",
                "viewKey": "viewValue",
                "newViewKey": "newViewValue",
                "globalKey": "globalValue",
                "newGlobalKey": "newGlobalValue",
            ]
        )
    }

    // MARK: - Global Attributes

    func testWhenGlobalAttributesAreUpdated_eventsHaveTheUpdate() throws {
        let scope: RUMViewScope = .mockWith(parent: parent)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    globalAttributes: ["globalKey": "globalValue"],
                    attributes: ["viewKey": "viewValue"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        var event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["viewKey": "viewValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["globalKey": "globalValue", "viewKey": "viewValue"])

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(
                    globalAttributes: ["globalKey": "newGlobalValue"],
                    attributes: ["viewKey": "newViewValue"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        // View scope is stopped with the final snapshot of attributes
        DDAssertDictionariesEqual(scope.attributes, ["viewKey": "newViewValue", "globalKey": "newGlobalValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["globalKey": "newGlobalValue", "viewKey": "newViewValue"])
    }

    func testViewAttributesTakePrecedenceOverGlobalAttributes() throws {
        let scope: RUMViewScope = .mockWith(parent: parent)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    globalAttributes: ["key": "globalValue"],
                    attributes: ["key": "viewValue"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )
        // Then
        var event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "viewValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["key": "viewValue"])

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(
                    globalAttributes: ["key": "newGlobalValue"],
                    attributes: ["key": "newViewValue"],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )
        // Then
        event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "newViewValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["key": "newViewValue"])
    }

    func testCommandAttributesTakePrecendenceOverViewAttributesAndGlobalAttributes() throws {
        let scope: RUMViewScope = .mockWith(parent: parent)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    globalAttributes: ["key": "globalValue"],
                    attributes: ["key": "viewValue"]
                ),
                context: context,
                writer: writer
            )
        )
        // Then
        var event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "viewValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["key": "viewValue"])

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddLongTaskCommand.mockWith(
                    globalAttributes: ["key": "globalValue"],
                    attributes: ["key": "localValue"]
                ),
                context: context,
                writer: writer
            )
        )
        // Then
        let longTaskEvent = try XCTUnwrap(writer.events(ofType: RUMLongTaskEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "viewValue"])
        DDAssertDictionariesEqual(longTaskEvent.context!.contextInfo, ["key": "localValue"])

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(
                    globalAttributes: ["key": "newGlobalValue"],
                    attributes: ["key": "newViewValue"]
                ),
                context: context,
                writer: writer
            )
        )
        // Then
        event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "newViewValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["key": "newViewValue"])
    }

    // Removing global attributes is immediately reflected in attributes sent on View Update events and on child events.
    func testWhenRemovingGlobalAttributes_eventsDoNotIncludeThem() throws {
        let scope: RUMViewScope = .mockWith(parent: parent)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    globalAttributes: ["globalKey": "globalValue"],
                    attributes: ["key": "viewValue"]
                ),
                context: context,
                writer: writer
            )
        )
        // Then
        var event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "viewValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["key": "viewValue", "globalKey": "globalValue"])

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(
                    globalAttributes: [:],
                    attributes: ["anotherViewKey": "anotherViewValue"]
                ),
                context: context,
                writer: writer
            )
        )
        // Then
        event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "viewValue", "anotherViewKey": "anotherViewValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["key": "viewValue", "anotherViewKey": "anotherViewValue"])

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(
                    globalAttributes: [:],
                    attributes: ["key": "newViewValue"]
                ),
                context: context,
                writer: writer
            )
        )
        // Then
        event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        DDAssertDictionariesEqual(scope.attributes, ["key": "newViewValue", "anotherViewKey": "anotherViewValue"])
        DDAssertDictionariesEqual(event.context!.contextInfo, ["key": "newViewValue", "anotherViewKey": "anotherViewValue"])
    }

    // MARK: - Resources Tracking

    func testItManagesResourceScopesLifecycle() throws {
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        XCTAssertEqual(scope.resourceScopes.count, 0)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 1)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 2)
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 1)
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 0)

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )
        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(event.view.resource.count, 1, "View should record 1 successful Resource")
        XCTAssertEqual(event.view.error.count, 1, "View should record 1 error due to second Resource failure")
    }

    func testGivenViewWithPendingResources_whenItGetsStopped_itDoesNotFinishUntilResourcesComplete() throws {
        let viewStartTime = Date()
        var currentTime = viewStartTime
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // given
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )
        currentTime.addTimeInterval(1)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1", time: currentTime),
                context: context,
                writer: writer
            )
        )
        currentTime.addTimeInterval(1)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2", time: currentTime),
                context: context,
                writer: writer
            )
        )

        // when
        currentTime.addTimeInterval(1)
        XCTAssertTrue(
            scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            ),
            "The View should be kept alive as its Resources haven't yet finished loading"
        )

        // then
        currentTime.addTimeInterval(1)
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1", time: currentTime),
                context: context,
                writer: writer
            ),
            "The View should be kept alive as all its Resources haven't yet finished loading"
        )

        var event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertTrue(event.view.isActive ?? false, "View should stay active")

        currentTime.addTimeInterval(1)
        let lastResourceCompletionTime = currentTime
        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2", time: currentTime),
                context: context,
                writer: writer
            ),
            "The View should stop as all its Resources finished loading"
        )

        event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(event.view.resource.count, 1, "View should record 1 successful Resource")
        XCTAssertEqual(event.view.error.count, 1, "View should record 1 error due to second Resource failure")
        XCTAssertFalse(event.view.isActive ?? true, "View should be inactive")
        XCTAssertEqual(event.view.timeSpent, lastResourceCompletionTime.timeIntervalSince(viewStartTime).dd.toInt64Nanoseconds, "View should last until the last resource completes")
    }

    func testGivenViewWithUnfinishedResources_whenNextViewsAreStarted_itNoLongerUpdatesTimeSpent() throws {
        let view1StartTime = Date()
        var currentTime = view1StartTime
        let view1 = ViewIdentifier("view1")

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: view1,
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // given
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: view1),
                context: context,
                writer: writer
            )
        )
        currentTime.addTimeInterval(1)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/dangling/resource", time: currentTime),
                context: context,
                writer: writer
            )
        )

        // when (start 2 next views)
        currentTime.addTimeInterval(1)
        let nextViewStartTime = currentTime
        var nextViewStartCommand = RUMStartViewCommand.mockWith(time: currentTime, identity: ViewIdentifier(String.mockRandom()))
        XCTAssertTrue(
            scope.process(command: nextViewStartCommand, context: context, writer: writer),
            "The View should be kept alive as `/dangling/resource` haven't yet finished loading"
        )
        currentTime.addTimeInterval(1)
        nextViewStartCommand = RUMStartViewCommand.mockWith(time: currentTime, identity: ViewIdentifier(String.mockRandom()))
        XCTAssertTrue(
            scope.process(command: nextViewStartCommand, context: context, writer: writer),
            "The View should be kept alive as `/dangling/resource` haven't yet finished loading"
        )

        let lastEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastEvent.view.resource.count, 0, "View should record no resources as `/dangling/resource` never finished")
        XCTAssertEqual(lastEvent.view.isActive, true, "View should remain active because it has pending resource")
        XCTAssertEqual(lastEvent.view.timeSpent, nextViewStartTime.timeIntervalSince(view1StartTime).dd.toInt64Nanoseconds, "View should last until next view was started")
    }

    // MARK: - User Action Tracking

    func testItManagesContinuousUserActionScopeLifecycle() throws {
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        XCTAssertNil(scope.userActionScope)
        let actionName = String.mockRandom()
        XCTAssertTrue(
            scope.process(
                command: RUMStartUserActionCommand.mockWith(actionType: .swipe, name: actionName),
                context: context,
                writer: writer
            )
        )
        XCTAssertNotNil(scope.userActionScope)
        XCTAssertEqual(scope.userActionScope?.name, actionName)

        let secondAction = RUMStartUserActionCommand.mockWith(actionType: .swipe, name: .mockRandom())
        XCTAssertTrue(
            scope.process(
                command: secondAction,
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should ignore the next (only non-custom) UA if one is pending.")
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            RUM Action '\(secondAction.actionType)' on '\(secondAction.name)' was dropped, because another action is still active for the same view.
            """
        )

        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockWith(actionType: .custom, name: .mockRandom()),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should not change existing pending action when adding custom UA (but this custom action should be recorded anyway).")

        XCTAssertTrue(
            scope.process(
                command: RUMStopUserActionCommand.mockWith(actionType: .swipe),
                context: context,
                writer: writer
            )
        )
        XCTAssertNil(scope.userActionScope)

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )
        let viewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewEvent.view.action.count, 2, "View should record 2 actions: non-custom + instant custom")
    }

    func testItManagesDiscreteUserActionScopeLifecycle() throws {
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertNil(scope.userActionScope)
        let actionName = String.mockRandom()
        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .tap, name: actionName),
                context: context,
                writer: writer
            )
        )
        XCTAssertNotNil(scope.userActionScope)
        XCTAssertEqual(scope.userActionScope?.name, actionName)

        let secondAction = RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .tap, name: .mockRandom())
        XCTAssertTrue(
            scope.process(
                command: secondAction,
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should ignore the next (only non-custom) UA if one is pending.")
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            RUM Action '\(secondAction.actionType)' on '\(secondAction.name)' was dropped, because another action is still active for the same view.
            """
        )

        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockWith(actionType: .custom, name: .mockRandom()),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should not change existing pending action when adding custom UA (but this custom action should be recorded anyway).")

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )
        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(event.view.action.count, 2, "View should record 2 actions: non-custom + instant custom")
    }

    func testGivenViewWithPendingAction_whenCustomActionIsAdded_itSendsItInstantly() throws {
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )

        // Given
        currentTime.addTimeInterval(0.5)

        let pendingActionName: String = .mockRandom()
        _ = scope.process(
                command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .tap, name: pendingActionName),
                context: context,
                writer: writer
            )
        XCTAssertEqual(scope.userActionScope?.name, pendingActionName)

        // When
        let customActionName: String = .mockRandom()
        _ = scope.process(
                command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .custom, name: customActionName),
                context: context,
                writer: writer
            )

        // Then
        XCTAssertEqual(scope.userActionScope?.name, pendingActionName, "It should not alter pending action")

        let lastViewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        let firstActionEvent = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(lastViewEvent.view.action.count, 1, "View should record 1 only custom action (pending action is not yet finished)")
        XCTAssertEqual(firstActionEvent.action.target?.name, customActionName)
        XCTAssertEqual(firstActionEvent.source, .ios)
        XCTAssertEqual(firstActionEvent.service, "test-service")
        XCTAssertEqual(firstActionEvent.version, "test-version")
        XCTAssertEqual(firstActionEvent.buildVersion, "test-build")
        XCTAssertEqual(firstActionEvent.buildId, context.buildId)
        XCTAssertEqual(firstActionEvent.device?.name, "device-name")
        XCTAssertEqual(firstActionEvent.os?.name, "device-os")
        XCTAssertEqual(firstActionEvent.os?.version, "os-version")
        XCTAssertEqual(firstActionEvent.os?.build, "os-build")
    }

    func testGivenViewWithNoPendingAction_whenCustomActionIsAdded_itSendsItInstantly() throws {
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )

        // Given
        currentTime.addTimeInterval(0.5)

        XCTAssertNil(scope.userActionScope)

        // When
        let customActionName: String = .mockRandom()
        _ = scope.process(
                command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .custom, name: customActionName),
                context: context,
                writer: writer
            )

        // Then
        XCTAssertNil(scope.userActionScope, "It should not count custom action as pending")

        let lastViewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        let firstActionEvent = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(lastViewEvent.view.action.count, 1, "View should record custom action")
        XCTAssertEqual(firstActionEvent.action.target?.name, customActionName)
        XCTAssertEqual(firstActionEvent.source, .ios)
        XCTAssertEqual(firstActionEvent.service, "test-service")
        XCTAssertEqual(firstActionEvent.version, "test-version")
        XCTAssertEqual(firstActionEvent.buildVersion, "test-build")
        XCTAssertEqual(firstActionEvent.buildId, context.buildId)
        XCTAssertEqual(firstActionEvent.device?.name, "device-name")
        XCTAssertEqual(firstActionEvent.os?.name, "device-os")
        XCTAssertEqual(firstActionEvent.os?.version, "os-version")
        XCTAssertEqual(firstActionEvent.os?.build, "os-build")
    }

    func testWhenDiscreteUserActionHasFrustration_itSendsFrustrationCount() throws {
        // Given
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        // When
        (0..<5).forEach { i in
            XCTAssertTrue(
                scope.process(
                    command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .tap),
                    context: context,
                    writer: writer
                )
            )

            XCTAssertTrue(
                scope.process(
                    command: RUMAddCurrentViewErrorCommand.mockRandom(),
                    context: context,
                    writer: writer
                )
            )

            currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)
        }

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(event.view.frustration?.count, 5)
    }

    func testWhenTwoTapActionsTrackedSequentially_thenHigherPriorityInstrumentationWins() throws {
        func actionName(for instrumentationType: InstrumentationType) -> String {
            switch instrumentationType {
            case .manual: return "Manual action"
            case .uikit: return "UIKit action"
            case .swiftuiAutomatic: return "Automatic SwiftUI action"
            case .swiftui: return "SwiftUI action"
            }
        }

        /// Simulates two consecutive tap actions, triggered by different instrumentation types,
        /// and asserts that the higher priority action is tracked.
        /// - Parameters:
        ///   - firstTap: The type of instrumentation that tracks the first tap.
        ///   - secondTap: The type of instrumentation that tracks the second tap.
        ///   - expectedActionName: The expected action name after the second tap is processed.
        func testTapActions(
            firstTap: InstrumentationType, secondTap: InstrumentationType, expectedActionName: String
        ) throws {
            let firstActionName = actionName(for: firstTap)
            let secondActionName = actionName(for: secondTap)

            var currentTime = Date()
            let scope = RUMViewScope(
                isInitialView: false,
                parent: parent,
                dependencies: .mockAny(),
                identity: .mockViewIdentifier(),
                path: .mockAny(),
                name: .mockAny(),
                customTimings: [:],
                startTime: currentTime,
                serverTimeOffset: .zero,
                interactionToNextViewMetric: INVMetricMock(),
                viewIndexInSession: .mockAny()
            )
            _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )

            // Given: The first tap action is tracked
            _ = scope.process(
                command: RUMAddUserActionCommand.mockWith(
                    time: currentTime, instrumentation: firstTap, actionType: .tap, name: firstActionName
                ),
                context: context,
                writer: writer
            )

            // When: The second tap action is tracked shortly after
            currentTime.addTimeInterval(.mockRandom(min: 0, max: RUMUserActionScope.Constants.discreteActionTimeoutDuration))
            _ = scope.process(
                command: RUMAddUserActionCommand.mockWith(
                    time: currentTime, instrumentation: secondTap, actionType: .tap, name: secondActionName
                ),
                context: context,
                writer: writer
            )

            // Then: Assert that the higher-priority action is the one being tracked
            currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)
            _ = scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )

            let viewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
            let actionName = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last?.action.target?.name)
            XCTAssertEqual(viewEvent.view.action.count, 1)
            XCTAssertEqual(
                actionName,
                expectedActionName,
                "When \(firstActionName) is followed by \(secondActionName) it should sent \(expectedActionName) not \(actionName)"
            )
        }

        try testTapActions(firstTap: .uikit, secondTap: .swiftui, expectedActionName: actionName(for: .swiftui))
        try testTapActions(firstTap: .uikit, secondTap: .manual, expectedActionName: actionName(for: .manual))
        try testTapActions(firstTap: .uikit, secondTap: .swiftuiAutomatic, expectedActionName: actionName(for: .swiftuiAutomatic))
        try testTapActions(firstTap: .swiftui, secondTap: .manual, expectedActionName: actionName(for: .manual))
        try testTapActions(firstTap: .swiftui, secondTap: .uikit, expectedActionName: actionName(for: .swiftui))
        try testTapActions(firstTap: .swiftui, secondTap: .swiftuiAutomatic, expectedActionName: actionName(for: .swiftui))
        try testTapActions(firstTap: .manual, secondTap: .uikit, expectedActionName: actionName(for: .manual))
        try testTapActions(firstTap: .manual, secondTap: .swiftui, expectedActionName: actionName(for: .manual))
        try testTapActions(firstTap: .manual, secondTap: .swiftuiAutomatic, expectedActionName: actionName(for: .manual))
    }

    // MARK: - Error Tracking

    func testWhenViewErrorIsAdded_itSendsErrorEventAndViewUpdateEvent() throws {
        let completionExpectation = expectation(description: "Error processing completion")

        let hasReplay: Bool = .mockRandom()
        var context = self.context
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: hasReplay))

        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(
                    time: currentTime,
                    message: "view error",
                    source: .source,
                    stack: nil,
                    completionHandler: completionExpectation.fulfill
                ),
                context: context,
                writer: writer
            )
        )

        wait(for: [completionExpectation], timeout: 0)

        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(error.date, Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 1).timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(error.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(error.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(error.session.type, .user)
        XCTAssertEqual(error.session.hasReplay, hasReplay)
        DDTAssertValidRUMUUID(error.view.id)
        XCTAssertEqual(error.view.url, "UIViewController")
        XCTAssertEqual(error.view.name, "ViewName")
        XCTAssertNil(error.usr)
        XCTAssertNil(error.connectivity)
        DDTAssertValidRUMUUID(error.error.id)
        XCTAssertEqual(error.error.type, "abc")
        XCTAssertEqual(error.error.message, "view error")
        XCTAssertEqual(error.error.category, .exception)
        XCTAssertEqual(error.error.source, .source)
        XCTAssertEqual(error.error.sourceType, .ios)
        XCTAssertNil(error.error.stack)
        XCTAssertTrue(error.error.isCrash == false)
        XCTAssertNil(error.error.resource)
        XCTAssertNil(error.action)
        XCTAssertEqual(error.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(error.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(error.source, .ios)
        XCTAssertEqual(error.service, "test-service")
        XCTAssertEqual(error.version, "test-version")
        XCTAssertEqual(error.buildVersion, "test-build")
        XCTAssertEqual(error.buildId, context.buildId)
        XCTAssertEqual(error.device?.name, "device-name")
        XCTAssertEqual(error.os?.name, "device-os")
        XCTAssertEqual(error.os?.version, "os-version")
        XCTAssertEqual(error.os?.build, "os-build")

        let viewUpdate = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewUpdate.view.error.count, 1)
    }

    func testWhenViewErrorIsAddedWithConfiguredSource_itSendsErrorEventWithCorrectSource() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let source = String.mockAnySource()

        let customContext: DatadogContext = .mockWith(source: source)

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: .mockViewIdentifier()),
                context: customContext,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime, message: "view error", source: .source, stack: nil),
                context: customContext,
                writer: writer
            )
        )

        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(error.source, .init(rawValue: source))
        // Configured source should not muck with sourceType, which is set separately.
        XCTAssertEqual(error.error.sourceType, .ios)
    }

    func testGivenStartedView_whenCrossPlatformErrorIsAdded_itSendsCorrectErrorEvent() throws {
        let completionExpectation = expectation(description: "Error processing completion")

        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        let customSource = String.mockAnySource()
        let expectedSource = RUMErrorEvent.Source(rawValue: customSource)
        let customContext: DatadogContext = .mockWith(
            service: "test-service",
            source: customSource
        )

        let scope: RUMViewScope = .mockWith(
            parent: parent,
            dependencies: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockAny(),
                context: customContext,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        let customSourceType = String.mockAnySourceType()
        let expectedSourceType = RUMErrorSourceType.init(rawValue: customSourceType)
        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(
                    attributes: [
                        CrossPlatformAttributes.errorSourceType: customSourceType,
                        CrossPlatformAttributes.errorIsCrash: true
                    ],
                    completionHandler: completionExpectation.fulfill
                ),
                context: customContext,
                writer: writer
            )
        )

        wait(for: [completionExpectation], timeout: 0)

        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        DDTAssertValidRUMUUID(error.error.id)
        XCTAssertEqual(error.error.sourceType, expectedSourceType)
        XCTAssertTrue(error.error.isCrash ?? false)
        XCTAssertEqual(error.source, expectedSource)
        XCTAssertEqual(error.error.category, .exception)
        XCTAssertEqual(error.service, "test-service")

        let viewUpdate = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewUpdate.view.error.count, 1)
        XCTAssertEqual(viewUpdate.source, RUMViewEvent.Source(rawValue: customSource))
        XCTAssertEqual(viewUpdate.service, "test-service")
    }

    func testGivenStartedView_whenErrorWithAttributesIsAdded_itDoesNotUpdateViewAttributes() throws {
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: hasReplay))

        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    time: currentTime,
                    attributes: [
                        "test_attribute": "abc",
                        "other_attribute": "my attribute"
                    ],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(
                    time: currentTime,
                    message: "view error",
                    source: .source,
                    stack: nil,
                    attributes: ["other_attribute": "overwritten", "foo": "bar"]
                ),
                context: context,
                writer: writer
            )
        )

        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        DDAssertDictionariesEqual(error.context!.contextInfo, ["test_attribute": "abc", "other_attribute": "overwritten", "foo": "bar"])

        XCTAssertEqual(scope.attributes["test_attribute"] as? String, "abc")
        XCTAssertEqual(scope.attributes["other_attribute"] as? String, "my attribute")
        XCTAssertNil(scope.attributes["foo"])
    }

    func testGivenStartedView_whenErrorWithFingerprintAttributesIsAdded_itAddsFingerprintToError() throws {
        // Given
        let hasReplay: Bool = .mockRandom()
        let fakeFingerprint: String = .mockRandom()
        var context = self.context
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: hasReplay))
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: [:], identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(
                    time: currentTime,
                    message: "view error",
                    source: .source,
                    stack: nil,
                    attributes: [
                        RUM.Attributes.errorFingerprint: fakeFingerprint
                    ]
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(error.error.fingerprint, fakeFingerprint)
        XCTAssertNil(error.context!.contextInfo[RUM.Attributes.errorFingerprint])
    }

    func testGivenStartedView_whenErrorWithIncludeBinaryImagesAttributesIsAdded_itAddsBinaryImagesToError() throws {
        // Given
        let mockBacktrace: BacktraceReport = .mockRandom()
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: hasReplay))
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(
                backtraceReporter: BacktraceReporterMock(backtrace: mockBacktrace)
            ),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: [:], identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(
                    time: currentTime,
                    message: "view error",
                    source: .source,
                    stack: nil,
                    attributes: [
                        CrossPlatformAttributes.includeBinaryImages: true
                    ]
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertNil(error.context?.contextInfo[CrossPlatformAttributes.includeBinaryImages])
        XCTAssertNotNil(error.error.binaryImages)
        XCTAssertEqual(error.error.binaryImages?.count, mockBacktrace.binaryImages.count)
        for i in 0..<mockBacktrace.binaryImages.count {
            let expected = mockBacktrace.binaryImages[i]
            if let actual = error.error.binaryImages?[i] {
                XCTAssertEqual(actual.arch, expected.architecture)
                XCTAssertEqual(actual.isSystem, expected.isSystemLibrary)
                XCTAssertEqual(actual.loadAddress, expected.loadAddress)
                XCTAssertEqual(actual.maxAddress, expected.maxAddress)
                XCTAssertEqual(actual.name, expected.libraryName)
                XCTAssertEqual(actual.uuid, expected.uuid)
            }
        }
    }

    func testWhenResourceIsFinishedWithError_itSendsViewUpdateEvent() throws {
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(attributes: ["foo": "bar"], identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorObject(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        let viewUpdate = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewUpdate.view.resource.count, 0, "Failed Resource should not be counted")
        XCTAssertEqual(viewUpdate.view.error.count, 1, "Failed Resource should be counted as Error")
    }

    func testWhenViewErrorIsAdded_itSendsErrorWithCorrectTimeSinceAppStart() throws {
        var context = self.context
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let appLauchToErrorTimeDiff = Int64.random(in: 10..<1_000_000)

        context.launchInfo = .mockWith(
            processLaunchDate: currentTime
        )

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime.addingTimeInterval(Double(appLauchToErrorTimeDiff)), message: "view error", source: .source, stack: nil),
                context: context,
                writer: writer
            )
        )

        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(error.error.timeSinceAppStart, appLauchToErrorTimeDiff * 1_000)
    }

    // MARK: - View Hitches

    func testWhenThereAreHitches_theViewUpdatesContainsSlowFrames() {
        // Given
        var hitches: [Hitch] = []
        (0...Int.mockRandom(min: 0, max: 1_000)).forEach {
            hitches.append((start: TimeInterval($0).dd.toInt64Nanoseconds, duration: 0.016.dd.toInt64Nanoseconds))
        }
        let hitchesDuration = TimeInterval.ddFromNanoseconds( hitches.map { $0.duration }.reduce(0, +))
        let viewHitchesReaderFactory = { ViewHitchesMock(hitchesDataModel: (hitches: hitches, hitchesDuration: hitchesDuration)) }
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(viewHitchesReaderFactory: viewHitchesReaderFactory),
            identity: .mockViewIdentifier(),
            path: .mockRandom(),
            name: .mockRandom(),
            customTimings: [:],
            startTime: .mockAny(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: nil,
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(
                command: RUMStartViewCommand.mockWith(),
                context: context,
                writer: writer
        )

        _ = scope.process(
            command: RUMAddViewTimingCommand.mockAny(),
            context: context,
            writer: writer
        )

        // Resources
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2"),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2"),
            context: context,
            writer: writer
        )

        _ = scope.process(
            command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(),
            context: context,
            writer: writer
        )

        _ = scope.process(
            command: RUMStopViewCommand.mockAny(),
            context: context,
            writer: writer
        )

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)

        XCTAssertEqual(viewEvents.count, 6)
        viewEvents.forEach {
            XCTAssertEqual($0.view.slowFrames?.count, hitches.count)
        }
    }

    func testWhenAppHangsAndViewHitchesAreDisabled_theRatesAreNotCalculated() {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(hasAppHangsEnabled: false, viewHitchesReaderFactory: { nil }),
            identity: .mockViewIdentifier(),
            path: .mockRandom(),
            name: .mockRandom(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: nil,
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime),
                context: context,
                writer: writer
        )

        currentTime.addTimeInterval(10)

        _ = scope.process(
            command: RUMStopViewCommand.mockWith(time: currentTime),
            context: context,
            writer: writer
        )

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)

        XCTAssertEqual(viewEvents.count, 2)
        let stopViewEvent = viewEvents.last
        XCTAssertNil(stopViewEvent?.view.slowFrames)
        XCTAssertNil(stopViewEvent?.view.slowFramesRate)
        XCTAssertNil(stopViewEvent?.view.freezeRate)
    }

    func testWhenViewDurationIsTooSmall_theRatesAreNotCalculated() {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        var hitches: [Hitch] = []
        (0...Int.mockRandom(min: 0, max: 1_000)).forEach {
            hitches.append((start: TimeInterval($0).dd.toInt64Nanoseconds, duration: 0.016.dd.toInt64Nanoseconds))
        }
        let hitchesDuration = TimeInterval.ddFromNanoseconds( hitches.map { $0.duration }.reduce(0, +))
        let viewHitchesReaderFactory = { ViewHitchesMock(hitchesDataModel: (hitches: hitches, hitchesDuration: hitchesDuration)) }
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(hasAppHangsEnabled: true, viewHitchesReaderFactory: viewHitchesReaderFactory),
            identity: .mockViewIdentifier(),
            path: .mockRandom(),
            name: .mockRandom(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: nil,
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime),
                context: context,
                writer: writer
        )

        currentTime.addTimeInterval(0.9)

        _ = scope.process(
            command: RUMStopViewCommand.mockWith(time: currentTime),
            context: context,
            writer: writer
        )

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)

        XCTAssertEqual(viewEvents.count, 2)
        let stopViewEvent = viewEvents.last
        XCTAssertEqual(stopViewEvent?.view.slowFrames?.count, hitches.count)
        XCTAssertNil(stopViewEvent?.view.slowFramesRate)
        XCTAssertNil(stopViewEvent?.view.freezeRate)
    }

    func testWhenThereAreViewHitches_theStopViewEventHasSlowFramesRate() {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        var hitches: [Hitch] = []
        (0..<10).forEach {
            hitches.append((start: TimeInterval($0).dd.toInt64Nanoseconds, duration: 0.016.dd.toInt64Nanoseconds))
        }
        let hitchesDuration = TimeInterval.ddFromNanoseconds( hitches.map { $0.duration }.reduce(0, +))
        let viewHitchesReaderFactory = { ViewHitchesMock(hitchesDataModel: (hitches: hitches, hitchesDuration: hitchesDuration)) }
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(viewHitchesReaderFactory: viewHitchesReaderFactory),
            identity: .mockViewIdentifier(),
            path: .mockRandom(),
            name: .mockRandom(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: nil,
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime),
                context: context,
                writer: writer
        )

        currentTime.addTimeInterval(1)

        _ = scope.process(
            command: RUMAddViewTimingCommand.mockWith(time: currentTime),
            context: context,
            writer: writer
        )

        currentTime.addTimeInterval(9)

        _ = scope.process(
            command: RUMStopViewCommand.mockWith(time: currentTime),
            context: context,
            writer: writer
        )

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)

        XCTAssertEqual(viewEvents.count, 3)
        for event in viewEvents.dropLast() {
            XCTAssertNil(event.view.slowFramesRate)
        }
        let stopViewEvent = viewEvents.last
        XCTAssertEqual(stopViewEvent?.view.slowFrames?.count, hitches.count)
        // The rate is only calculated in the Stop View event
        XCTAssertEqual(stopViewEvent?.view.slowFramesRate, 16)
    }

    func testWhenThereAreAppHangs_theStopViewEventHasFreezeRate() {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(hasAppHangsEnabled: true),
            identity: .mockViewIdentifier(),
            path: .mockRandom(),
            name: .mockRandom(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: nil,
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime),
                context: context,
                writer: writer
        )

        currentTime.addTimeInterval(2)

        _ = scope.process(
            command: RUMAddCurrentViewAppHangCommand.mockWith(
                time: currentTime,
                message: "App Hang",
                type: "AppHang",
                stack: "<hang stack>",
                hangDuration: 5
            ),
            context: context,
            writer: writer
        )

        currentTime.addTimeInterval(8)

        _ = scope.process(
            command: RUMStopViewCommand.mockWith(time: currentTime),
            context: context,
            writer: writer
        )

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)

        XCTAssertEqual(viewEvents.count, 3)
        for event in viewEvents.dropLast() {
            XCTAssertNil(event.view.freezeRate)
        }
        // The rate is only calculated in the Stop View event
        let stopViewEvent = viewEvents.last
        XCTAssertEqual(stopViewEvent?.view.freezeRate, 0.5.hours)
    }

    func testWhenViewErrorIsAdded_ButErrorEventDiscarded_itCallsCompletionHandler() throws {
        let completionExpectation = expectation(description: "Error processing completion")

        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(
                eventBuilder: RUMEventBuilder(
                    eventsMapper: .mockWith(errorEventMapper: { _ in nil })
                )
            ),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(
                    time: currentTime,
                    message: "view error",
                    source: .source,
                    stack: nil,
                    completionHandler: completionExpectation.fulfill
                ),
                context: context,
                writer: writer
            )
        )

        wait(for: [completionExpectation], timeout: 0)
        XCTAssertTrue(writer.events(ofType: RUMErrorEvent.self).isEmpty)
        XCTAssertFalse(writer.events(ofType: RUMViewEvent.self).isEmpty)
    }

    // MARK: - App Hangs

    func testWhenViewAppHangIsTracked_itSendsErrorEventAndViewUpdateEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let hangDuration: TimeInterval = .mockRandom(min: 1, max: 10)
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewAppHangCommand.mockWith(
                    time: currentTime,
                    message: "App Hang",
                    type: "AppHang",
                    stack: "<hang stack>",
                    hangDuration: hangDuration
                ),
                context: context,
                writer: writer
            )
        )

        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(error.date, Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 1).timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(error.view.url, "UIViewController")
        XCTAssertEqual(error.view.name, "ViewName")
        DDTAssertValidRUMUUID(error.error.id)
        XCTAssertEqual(error.error.message, "App Hang")
        XCTAssertEqual(error.error.type, "AppHang")
        XCTAssertEqual(error.error.stack, "<hang stack>")
        XCTAssertEqual(error.error.category, .appHang)
        XCTAssertEqual(error.error.source, .source)
        XCTAssertEqual(error.error.sourceType, .ios)
        XCTAssertTrue(error.error.isCrash == false)
        XCTAssertEqual(error.freeze?.duration, hangDuration.dd.toInt64Nanoseconds)

        let viewUpdate = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewUpdate.view.error.count, 1)
    }

    // MARK: - Long tasks

    func testWhenLongTaskIsAdded_itSendsLongTaskEventAndViewUpdateEvent() throws {
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: hasReplay))

        let startViewDate: Date = .mockDecember15th2019At10AMUTC()

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: startViewDate,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: startViewDate, attributes: ["foo": "bar"], identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        let addLongTaskDate = startViewDate + 1.0
        let duration: TimeInterval = 1.0

        XCTAssertTrue(
            scope.process(
                command: RUMAddLongTaskCommand(time: addLongTaskDate, attributes: ["foo": "bar"], duration: duration),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMLongTaskEvent.self).last)

        let longTaskStartingDate = addLongTaskDate - duration

        XCTAssertEqual(event.action?.id.stringValue, scope.context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.hasReplay, hasReplay)
        XCTAssertNil(event.connectivity)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.date, longTaskStartingDate.timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(event.dd.session?.plan, .plan1)
        XCTAssertEqual(event.source, .ios)
        DDTAssertValidRUMUUID(event.longTask.id)
        XCTAssertEqual(event.longTask.duration, (1.0).dd.toInt64Nanoseconds)
        XCTAssertTrue(event.longTask.isFrozenFrame == true)
        XCTAssertEqual(event.view.id, scope.viewUUID.toRUMDataFormat)
        XCTAssertNil(event.synthetics)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.device?.logicalCpuCount, 4)
        XCTAssertEqual(event.device?.totalRam, 2_048)
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.os?.version, "os-version")
        XCTAssertEqual(event.os?.build, "os-build")

        let viewUpdate = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewUpdate.view.longTask?.count, 1)
    }

    func testGivenStartedView_whenLongTaskWithAttributesIsAdded_itDoesNotUpdateViewAttributes() throws {
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: hasReplay))

        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(
                    time: currentTime,
                    attributes: [
                        "test_attribute": "abc",
                        "other_attribute": "my attribute"
                    ],
                    identity: .mockViewIdentifier()
                ),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)
        let duration: TimeInterval = 1.0

        XCTAssertTrue(
            scope.process(
                command: RUMAddLongTaskCommand(
                    time: currentTime,
                    attributes: ["foo": "bar", "test_attribute": "overwritten"],
                    duration: duration
                ),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMLongTaskEvent.self).last)
        DDAssertDictionariesEqual(event.context!.contextInfo, ["foo": "bar", "test_attribute": "overwritten", "other_attribute": "my attribute"])
        DDAssertDictionariesEqual(scope.attributes, ["test_attribute": "abc", "other_attribute": "my attribute"])
    }

    func testWhenLongTaskIsAddedWithConfiguredSource_itSendsLongTaskEventWithConfiguredSource() throws {
        let startViewDate: Date = .mockDecember15th2019At10AMUTC()

        let source = String.mockAnySource()
        let customContext: DatadogContext = .mockWith(source: source)

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: startViewDate,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: startViewDate, attributes: ["foo": "bar"], identity: .mockViewIdentifier()),
                context: customContext,
                writer: writer
            )
        )

        let addLongTaskDate = startViewDate + 1.0
        let duration: TimeInterval = 1.0

        XCTAssertTrue(
            scope.process(
                command: RUMAddLongTaskCommand(time: addLongTaskDate, attributes: ["foo": "bar"], duration: duration),
                context: customContext,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMLongTaskEvent.self).last)
        XCTAssertEqual(event.source, .init(rawValue: source))
    }

    // MARK: - Custom Timings Tracking

    func testGivenActiveView_whenCustomTimingIsRegistered_itSendsViewUpdateEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        // Given
        XCTAssertTrue(scope.isActiveView)
        XCTAssertEqual(scope.customTimings.count, 0)

        // When
        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-500000000ns"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.customTimings.count, 1)

        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-1000000000ns"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.customTimings.count, 2)

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))

        XCTAssertEqual(events.count, 3, "There should be 3 View updates sent")
        XCTAssertEqual(events[0].view.customTimings?.customTimingsInfo, [:])
        XCTAssertEqual(
            events[1].view.customTimings?.customTimingsInfo,
            ["timing-after-500000000ns": 500_000_000]
        )
        XCTAssertEqual(
            events[2].view.customTimings?.customTimingsInfo,
            ["timing-after-500000000ns": 500_000_000, "timing-after-1000000000ns": 1_000_000_000]
        )
    }

    func testGivenInactiveView_whenCustomTimingIsRegistered_itDoesNotSendViewUpdateEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        // Given
        XCTAssertFalse(scope.isActiveView)

        // When
        currentTime.addTimeInterval(0.5)

        _ = scope.process(
            command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-500000000ns"),
            context: context,
            writer: writer
        )

        // Then
        let lastEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastEvent.view.customTimings?.customTimingsInfo, [:])
    }

    func testGivenActiveView_whenCustomTimingIsRegistered_itSanitizesCustomTiming() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        // Given
        XCTAssertTrue(scope.isActiveView)
        XCTAssertEqual(scope.customTimings.count, 0)

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        currentTime.addTimeInterval(0.5)
        let originalTimingName = "timing1_.@$-()&+=Д"
        let sanitizedTimingName = "timing1_.@$-______"
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: originalTimingName),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.customTimings.count, 1)

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))

        XCTAssertEqual(events.count, 2, "There should be 2 View updates sent")
        XCTAssertEqual(events[0].view.customTimings?.customTimingsInfo, [:])
        XCTAssertEqual(
            events[1].view.customTimings?.customTimingsInfo,
            [sanitizedTimingName: 500_000_000]
        )
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            Custom timing '\(originalTimingName)' was modified to '\(sanitizedTimingName)' to match Datadog constraints.
            """
        )
    }

    // MARK: - Feature Flags

    func testGivenActiveView_whenFeatureFlagEvaluated_itAddsTheFeatureFlag() throws {
        // Given
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )
        let featureFlagCommand = RUMAddFeatureFlagEvaluationCommand.mockRandom()

        // When
        XCTAssertTrue(
            scope.process(
                command: featureFlagCommand,
                context: context,
                writer: writer
            )
        )

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))

        XCTAssertEqual(events.count, 2)
        let initialFlags = try XCTUnwrap(events[0].featureFlags)
        XCTAssertEqual(initialFlags.featureFlagsInfo.count, 0)
        let featureFlags = try XCTUnwrap(events[1].featureFlags)
        XCTAssertEqual(featureFlags.featureFlagsInfo.count, 1)
        XCTAssertEqual(featureFlags.featureFlagsInfo[featureFlagCommand.name] as! String, featureFlagCommand.value as! String)
    }

    func testGivenActiveView_whenFeatureFlagReEvaluated_itModifiesTheFeatureFlag() throws {
        // Given
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )
        let flagName: String = .mockRandom()
        let flagFinalValue: String = .mockRandom()

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddFeatureFlagEvaluationCommand.mockWith(
                    name: flagName
                ),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMAddFeatureFlagEvaluationCommand.mockWith(
                    name: flagName,
                    value: flagFinalValue
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))

        XCTAssertEqual(events.count, 3)
        let featureFlags = try XCTUnwrap(events[2].featureFlags)
        XCTAssertEqual(featureFlags.featureFlagsInfo.count, 1)
        XCTAssertEqual(featureFlags.featureFlagsInfo[flagName] as! String, flagFinalValue)
    }

    func testGivenActiveViewWithFeatureFlag_itSendsThoseFlagsWithErrors() throws {
        // Given
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )
        let mockFeatureFlagCommand: RUMAddFeatureFlagEvaluationCommand = .mockRandom()
        XCTAssertTrue(
            scope.process(
                command: mockFeatureFlagCommand,
                context: context,
                writer: writer
            )
        )

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockAny(),
                context: context,
                writer: writer
            )
        )

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self))

        XCTAssertEqual(events.count, 1)
        let featureFlags = try XCTUnwrap(events[0].featureFlags)
        XCTAssertEqual(featureFlags.featureFlagsInfo.count, 1)
        XCTAssertEqual(
            featureFlags.featureFlagsInfo[mockFeatureFlagCommand.name] as! String,
            mockFeatureFlagCommand.value as! String
        )
    }

    // MARK: - Stopped Session

    func testGivenSession_whenSessionStopped_itSendsViewUpdateWithStopped() throws {
        let initialDeviceTime: Date = .mockDecember15th2019At10AMUTC()
        let initialServerTimeOffset: TimeInterval = 120 // 2 minutes

        // Given
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: initialDeviceTime,
            serverTimeOffset: initialServerTimeOffset,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        parent.context.isSessionActive = false

        // When
        XCTAssertFalse(
            scope.process(
                command: RUMStopSessionCommand.mockAny(),
                context: context,
                writer: writer
            )
        )

        // Then
        XCTAssertFalse(scope.isActiveView)
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.session.isActive, false)
    }

    // MARK: - Dates Correction

    func testGivenViewStartedWithServerTimeDifference_whenDifferentEventsAreSend_itAppliesTheSameCorrectionToAll() throws {
        let initialDeviceTime: Date = .mockDecember15th2019At10AMUTC()
        let initialServerTimeOffset: TimeInterval = 120 // 2 minutes
        var currentDeviceTime = initialDeviceTime

        // Given
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: initialDeviceTime,
            serverTimeOffset: initialServerTimeOffset,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentDeviceTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
        )
        currentDeviceTime.addTimeInterval(1) // advance device time

        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1", time: currentDeviceTime),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2", time: currentDeviceTime),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1", time: currentDeviceTime),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2", time: currentDeviceTime),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentDeviceTime),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: currentDeviceTime),
            context: context,
            writer: writer
        )

        _ = scope.process(
                command: RUMStopViewCommand.mockWith(time: currentDeviceTime, identity: .mockViewIdentifier()),
                context: context,
                writer: writer
        )

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        let resourceEvents = writer.events(ofType: RUMResourceEvent.self)
        let errorEvents = writer.events(ofType: RUMErrorEvent.self)
        let actionEvents = writer.events(ofType: RUMActionEvent.self)

        let initialRealTime = initialDeviceTime.addingTimeInterval(initialServerTimeOffset)
        let expectedViewEventsDate = initialRealTime.timeIntervalSince1970.dd.toInt64Milliseconds
        let expectedOtherEventsDate = initialRealTime.addingTimeInterval(1).timeIntervalSince1970.dd.toInt64Milliseconds

        XCTAssertFalse(viewEvents.isEmpty)
        XCTAssertFalse(resourceEvents.isEmpty)
        XCTAssertFalse(errorEvents.isEmpty)
        XCTAssertFalse(actionEvents.isEmpty)

        viewEvents.forEach { view in
            XCTAssertEqual(view.date, expectedViewEventsDate)
        }
        resourceEvents.forEach { view in
            XCTAssertEqual(view.date, expectedOtherEventsDate)
        }
        errorEvents.forEach { view in
            XCTAssertEqual(view.date, expectedOtherEventsDate)
        }
        actionEvents.forEach { view in
            XCTAssertEqual(view.date, expectedOtherEventsDate)
        }
    }

    // MARK: ViewScope Counts Correction

    func testGivenViewScopeWithDependentActionsResourcesErrors_whenDroppingEvents_thenCountsAreAdjusted() throws {
        struct ResourceMapperHolder {
            var resourceEventMapper: RUM.ResourceEventMapper?
        }
        var resourceMapperHolder = ResourceMapperHolder()

        // Given an eventBuilder using an eventsMapper that:
        // - discards `RUMActionEvent` for `RUMAddUserActionCommand`
        // - discards `RUMErrorEvent` for `RUMAddCurrentViewErrorCommand`
        // - discards `RUMResourceEvent` from `RUMStartResourceCommand` /resource/1
        let eventBuilder = RUMEventBuilder(
            eventsMapper: .mockWith(
                errorEventMapper: { event in
                    nil
                },
                resourceEventMapper: {
                    resourceMapperHolder.resourceEventMapper?($0)
                },
                actionEventMapper: { _ in nil }
            )
        )
        let dependencies: RUMScopeDependencies = .mockWith(
            eventBuilder: eventBuilder
        )

        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: dependencies,
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewController",
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockAny(),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            )
        )

        XCTAssertEqual(scope.resourceScopes.count, 2)

        let resourceScope1 = try XCTUnwrap(scope.resourceScopes["/resource/1"])
        let resourceID1 = resourceScope1.resourceUUID.toRUMDataFormat

        resourceMapperHolder.resourceEventMapper = { event in
            return event.resource.id == resourceID1 ? nil : event
        }

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        XCTAssertEqual(scope.resourceScopes.count, 0)

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)

        // Then
        XCTAssertEqual(event.view.resource.count, 1, "After dropping 1 Resource event (out of 2), View should record 1 Resource")
        XCTAssertEqual(event.view.action.count, 0, "After dropping a User Action event, View should record no actions")
        XCTAssertEqual(event.view.error.count, 0, "After dropping an Error event, View should record 0 Errors")
        XCTAssertEqual(event.dd.documentVersion, 4, "It should create 4 view update.")
    }

    func testGivenViewScopeWithDroppingEventsMapper_whenProcessingApplicationStartAction_thenCountIsAdjusted() throws {
        let eventBuilder = RUMEventBuilder(
            eventsMapper: .mockWith(
                actionEventMapper: { event in
                    nil
                }
            )
        )
        let dependencies: RUMScopeDependencies = .mockWith(
            eventBuilder: eventBuilder
        )

        // Given
        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: dependencies,
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewController",
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(event.view.action.count, 0, "All actions, including ApplicationStart action should be dropped")
        XCTAssertEqual(event.dd.documentVersion, 1, "It should record only one view update")
    }

    // MARK: - Updating Fatal Error Context

    func testWhenViewIsStarted_itUpdatesFatalErrorContextWithView() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()

        // Given
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureScope: featureScope, fatalErrorContext: fatalErrorContext),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewController",
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // When
        featureScope.eventWriteContext { context, writer in
            _ = scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        }

        // Then
        let rumViewWritten = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last, "It should send view event")
        let rumViewInFatalErrorContext = try XCTUnwrap(fatalErrorContext.view)
        DDAssertReflectionEqual(rumViewWritten, rumViewInFatalErrorContext, "It must update fatal error context with the view event written")
    }

    // MARK: - Tracking Time To Network Settled Metric

    func testWhenViewIsStopped_itStopsTrackingTNSMetric() throws {
        let viewStartDate = Date()
        let viewName: String = .mockRandom()

        // Given
        let metric = TNSMetricMock()
        let scope = RUMViewScope(
            isInitialView: .mockAny(),
            parent: parent,
            dependencies: .mockWith(
                networkSettledMetricFactory: { date, name in
                    XCTAssertEqual(date, viewStartDate)
                    XCTAssertEqual(name, viewName)
                    return metric
                }
            ),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: viewName,
            customTimings: [:],
            startTime: viewStartDate,
            serverTimeOffset: .mockRandom(),
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(
            command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
            context: context,
            writer: writer
        )

        // Then
        XCTAssertTrue(metric.viewWasStopped)
    }

    // MARK: - Interaction To Next View Metric

    func testWhenViewIsStartedThenStopped_itUpdatesINVMetric() throws {
        let viewStartDate = Date()
        let viewID: RUMUUID = .mockRandom()

        // Given
        let metric = INVMetricMock()
        let scope = RUMViewScope(
            isInitialView: .mockAny(),
            parent: parent,
            dependencies: .mockWith(
                rumUUIDGenerator: RUMUUIDGeneratorMock(uuid: viewID)
            ),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: viewStartDate,
            serverTimeOffset: .mockRandom(),
            interactionToNextViewMetric: metric,
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(
            command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
            context: context,
            writer: writer
        )

        // Then
        let trackedViewStart = try XCTUnwrap(metric.trackedViewStarts.first)
        let trackedViewComplete = try XCTUnwrap(metric.trackedViewCompletes.first)
        XCTAssertEqual(trackedViewStart.viewStart, viewStartDate)
        XCTAssertEqual(trackedViewStart.viewID, viewID)
        XCTAssertEqual(trackedViewComplete, viewID)
        XCTAssertEqual(metric.trackedViewStarts.count, 1)
        XCTAssertEqual(metric.trackedViewCompletes.count, 1)
    }

    // MARK: - Cross Platform View Attributes

    func testGivenAStartedView_whenItSetsAnInternalViewAttribute_itSetsTheAttribute() {
        // Given
        let viewStartDate = Date()
        let viewID: RUMUUID = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: .mockAny(),
            parent: parent,
            dependencies: .mockWith(
                rumUUIDGenerator: RUMUUIDGeneratorMock(uuid: viewID)
            ),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: viewStartDate,
            serverTimeOffset: .mockRandom(),
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // When
        let mockKey: String = .mockRandom()
        let mockValue: String = .mockRandom()
        _ = scope.process(
            command: RUMAddViewAttributesCommand(
                time: .mockAny(),
                attributes: [mockKey: mockValue],
                areInternalAttributes: true
            ),
            context: context,
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.internalAttributes[mockKey] as? String, mockValue)
    }

    func testGivenAStartedView_whenItSetsAnExitingInternalViewAttribute_itSetsTheAttribute() {
        // Given
        let viewStartDate = Date()
        let viewID: RUMUUID = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: .mockAny(),
            parent: parent,
            dependencies: .mockWith(
                rumUUIDGenerator: RUMUUIDGeneratorMock(uuid: viewID)
            ),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: viewStartDate,
            serverTimeOffset: .mockRandom(),
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        let mockKey: String = .mockRandom()
        let mockValue: String = .mockRandom()
        _ = scope.process(
            command: RUMAddViewAttributesCommand(
                time: .mockAny(),
                attributes: [mockKey: mockValue],
                areInternalAttributes: true
            ),
            context: context,
            writer: writer
        )

        // When
        let updatedValue: String = .mockRandom()
        _ = scope.process(
            command: RUMAddViewAttributesCommand(
                time: .mockAny(),
                attributes: [mockKey: updatedValue],
                areInternalAttributes: true
            ),
            context: context,
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.internalAttributes[mockKey] as? String, updatedValue)
    }

    func testGivenAStoppedView_whenItSetsAnInternalViewAttribute_itDoesNotSetTheAttribute() {
        // Given
        let viewStartDate = Date()
        let viewID: RUMUUID = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: .mockAny(),
            parent: parent,
            dependencies: .mockWith(
                rumUUIDGenerator: RUMUUIDGeneratorMock(uuid: viewID)
            ),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: viewStartDate,
            serverTimeOffset: .mockRandom(),
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        // When
        let mockKey: String = .mockRandom()
        let mockValue: String = .mockRandom()
        _ = scope.process(
            command: RUMAddViewAttributesCommand(
                time: .mockAny(),
                attributes: [mockKey: mockValue],
                areInternalAttributes: true
            ),
            context: context,
            writer: writer
        )

        // Then
        XCTAssertNil(scope.internalAttributes[mockKey])
    }

    // MARK: - Flutter First Build Complete

    func testGivenFCBInternalAttribute_itSetsTheValueOnTheViewEvent() throws {
        // Given
        let viewStartDate = Date()
        let viewID: RUMUUID = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: .mockAny(),
            parent: parent,
            dependencies: .mockWith(
                rumUUIDGenerator: RUMUUIDGeneratorMock(uuid: viewID)
            ),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: viewStartDate,
            serverTimeOffset: .mockRandom(),
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )
        let fbcValue = Int64.mockRandom(min: 0)
        _ = scope.process(
            command: RUMAddViewAttributesCommand(
                time: .mockAny(),
                attributes: [CrossPlatformAttributes.flutterFirstBuildComplete: fbcValue],
                areInternalAttributes: true
            ),
            context: context,
            writer: writer
        )

        // When
        // Though this property would be unlikely to be set during StartView, processing
        // the StartViewCommand will give us a view update, which is what we want.
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
            context: context,
            writer: writer
        )

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))
        let lastEvent = events.last!
        XCTAssertEqual(lastEvent.view.performance?.fbc?.timestamp, fbcValue)
    }

    // Custom INV Values
    func testGivenCustomINVValues_itSetsTheValueOnTheViewEvent() throws {
        // Given
        let viewStartDate = Date()
        let viewID: RUMUUID = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: .mockAny(),
            parent: parent,
            dependencies: .mockWith(
                rumUUIDGenerator: RUMUUIDGeneratorMock(uuid: viewID)
            ),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: viewStartDate,
            serverTimeOffset: .mockRandom(),
            interactionToNextViewMetric: nil,
            viewIndexInSession: .mockAny()
        )

        // When
        let invValue = Int64.mockRandom(min: 0, max: 100_000_000)
        _ = scope.process(
            command: RUMAddViewAttributesCommand(
                time: .mockAny(),
                attributes: [CrossPlatformAttributes.customINVValue: invValue],
                areInternalAttributes: true
            ),
            context: context,
            writer: writer
        )

        _ = scope.process(
            command: RUMStopViewCommand.mockAny(),
            context: context,
            writer: writer
        )

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))
        let lastEvent = events.last!
        XCTAssertEqual(lastEvent.view.interactionToNextViewTime, invValue)
    }
    // MARK: - Has replay

    func testViewUpdate_onceHasReplayIsTrueItRemainsTrue() throws {
        // Given
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: false))

        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(scope.isActiveView)

        // When
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: true))
        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-500000000ns"),
                context: context,
                writer: writer
            )
        )

        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: false))
        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-500000000ns"),
                context: context,
                writer: writer
            )
        )

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))
        XCTAssertEqual(events.count, 3, "There should be 3 View updates sent")
        XCTAssertEqual(events[0].session.hasReplay, false)
        XCTAssertEqual(events[1].session.hasReplay, true)
        XCTAssertEqual(events[2].session.hasReplay, true)
    }

    // MARK: - View Attributes
    @available(iOS 13.0, tvOS 13.0, *)
    @MainActor
    func testAccessibilityAttributesInViewEvents() throws {
        // Given
        let mockAccessibilityState = AccessibilityInfo(
            textSize: "medium",
            screenReaderEnabled: false,
            boldTextEnabled: true,
            reduceTransparencyEnabled: nil,
            reduceMotionEnabled: nil,
            buttonShapesEnabled: nil,
            invertColorsEnabled: nil,
            increaseContrastEnabled: nil,
            assistiveSwitchEnabled: nil,
            assistiveTouchEnabled: nil,
            videoAutoplayEnabled: nil,
            closedCaptioningEnabled: nil,
            monoAudioEnabled: nil,
            shakeToUndoEnabled: nil,
            reducedAnimationsEnabled: nil,
            shouldDifferentiateWithoutColor: nil,
            grayscaleEnabled: nil,
            singleAppModeEnabled: nil,
            onOffSwitchLabelsEnabled: nil,
            speakScreenEnabled: nil,
            speakSelectionEnabled: nil,
            rtlEnabled: nil
        )

        let mockAccessibilityReader = AccessibilityReaderMock(state: mockAccessibilityState)

        let mockParent = RUMContextProviderMock()
        let testContext = context

        let dependencies = RUMScopeDependencies.mockWith(
            accessibilityReader: mockAccessibilityReader
        )

        let scope = RUMViewScope(
            isInitialView: false,
            parent: mockParent,
            dependencies: dependencies,
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "MyView",
            customTimings: [:],
            startTime: .mockDecember15th2019At10AMUTC(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(identity: scope.identity),
            context: testContext,
            writer: writer
        )
        let initialExpectation = XCTestExpectation(description: "Initial accessibility state set")
        DispatchQueue.main.async {
            initialExpectation.fulfill()
        }
        wait(for: [initialExpectation], timeout: 1.0)

        // Then
        let initialEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)

        let initialAccessibilityData = try XCTUnwrap(
            initialEvent.view.accessibility
        )
        let finalExpectation = XCTestExpectation(description: "Initial accessibility state set")
        DispatchQueue.main.async {
            XCTAssertEqual(initialAccessibilityData.screenReaderEnabled, false)
            XCTAssertEqual(initialAccessibilityData.textSize, "medium")
            XCTAssertEqual(initialAccessibilityData.boldTextEnabled, true)
            finalExpectation.fulfill()
        }
        wait(for: [finalExpectation], timeout: 1.0)
    }

    func testNoAccessibilityAttributesWhenNil() throws {
        // Given
        let mockParent = RUMContextProviderMock()
        let testContext = context

        let dependencies = RUMScopeDependencies.mockWith(
            accessibilityReader: nil
        )

        let scope = RUMViewScope(
            isInitialView: false,
            parent: mockParent,
            dependencies: dependencies,
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "MyView",
            customTimings: [:],
            startTime: .mockDecember15th2019At10AMUTC(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: .mockAny()
        )

        // When
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(identity: scope.identity),
            context: testContext,
            writer: writer
        )

        // Then
        let viewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertNil(viewEvent.view.accessibility)
    }
}
