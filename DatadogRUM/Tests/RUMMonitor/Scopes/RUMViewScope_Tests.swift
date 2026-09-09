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

/// Mirrors `RUMViewScopeTests` but with `featureFlags[.viewUpdates] = true`.
/// With this flag the first write per view produces a full `RUMViewEvent`; every
/// subsequent write produces a `RUMViewUpdateEvent` (delta projection).
class RUMViewScope_Tests: XCTestCase {
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

    private let ff: RUM.Configuration.FeatureFlags = [.viewUpdates: true]

    private var totalViewEventCount: Int {
        writer.events(ofType: RUMViewEvent.self).count
            + writer.events(ofType: RUMViewUpdateEvent.self).count
    }

    // MARK: - View Lifecycle

    func testWhenViewIsStopped_itSendsUpdateEvent_andEndsTheScope() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
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

        // First write is a full RUMViewEvent.
        let fullEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(fullEvents.count, 1)
        let fullEvent = try XCTUnwrap(fullEvents.first)
        XCTAssertEqual(fullEvent.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds)
        DDTAssertValidRUMUUID(fullEvent.view.id)
        XCTAssertEqual(fullEvent.view.url, "UIViewController")
        XCTAssertEqual(fullEvent.view.name, "ViewName")
        XCTAssertTrue(try XCTUnwrap(fullEvent.view.isActive))
        XCTAssertEqual(fullEvent.dd.documentVersion, 1)
        XCTAssertEqual(fullEvent.source, .ios)
        XCTAssertEqual(fullEvent.service, "test-service")
        XCTAssertEqual(fullEvent.version, "test-version")
        XCTAssertEqual(fullEvent.buildVersion, "test-build")
        XCTAssertEqual(fullEvent.buildId, context.buildId)
        XCTAssertEqual(fullEvent.device?.name, "device-name")
        XCTAssertEqual(fullEvent.os?.name, "device-os")

        // Second write (stop view) is a delta RUMViewUpdateEvent.
        let updateEvents = writer.events(ofType: RUMViewUpdateEvent.self)
        XCTAssertEqual(updateEvents.count, 1)
        let update = try XCTUnwrap(updateEvents.first)

        // Always-forwarded fields.
        XCTAssertEqual(update.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(update.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(update.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(update.session.type, .user)
        DDTAssertValidRUMUUID(update.view.id)
        XCTAssertEqual(update.view.url, "UIViewController")
        XCTAssertEqual(update.dd.documentVersion, 2)
        XCTAssertNil(update.context)  // context unchanged between full event and stop → diffed to nil

        // Delta fields that changed.
        XCTAssertFalse(try XCTUnwrap(update.view.isActive))
        XCTAssertEqual(update.view.timeSpent, TimeInterval(2).dd.toInt64Nanoseconds)

        // Delta fields that did NOT change are nil in the update.
        XCTAssertNil(update.view.action)
        XCTAssertNil(update.view.error)
        XCTAssertNil(update.view.resource)
        // Stable identity fields (source, service, device, os) are diffed — nil if unchanged.
        XCTAssertNil(update.source)
        XCTAssertNil(update.service)
        XCTAssertNil(update.device)
        XCTAssertNil(update.os)
    }

    func testWhenViewIsStoppedInCITest_ciTestIsDiffed() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let fakeCiTestId: String = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(ciTest: .init(testExecutionId: fakeCiTestId), featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: .mockViewIdentifier()),
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
            )
        )

        XCTAssertEqual(totalViewEventCount, 2)

        // ciTest is on the first full event.
        let fullEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(fullEvent.session.type, .ciTest)
        XCTAssertEqual(fullEvent.ciTest?.testExecutionId, fakeCiTestId)

        // ciTest is diffed — unchanged between the two full-event snapshots → nil in update.
        let update = try XCTUnwrap(writer.events(ofType: RUMViewUpdateEvent.self).first)
        XCTAssertEqual(update.session.type, .ciTest)  // session.type always forwarded
        XCTAssertNil(update.ciTest)                    // ciTest diffed, unchanged → nil
        XCTAssertFalse(try XCTUnwrap(update.view.isActive))
    }

    func testWhenViewIsStoppedInSyntheticsTest_syntheticsIsDiffed() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let fakeTestId: String = .mockRandom()
        let fakeResultId: String = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(
                syntheticsTest: .init(injected: nil, resultId: fakeResultId, testId: fakeTestId, syntheticsInfo: [:]),
                featureFlags: ff
            ),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: .mockViewIdentifier()),
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
            )
        )

        XCTAssertEqual(totalViewEventCount, 2)

        let fullEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(fullEvent.session.type, .synthetics)
        XCTAssertEqual(fullEvent.synthetics?.testId, fakeTestId)
        XCTAssertEqual(fullEvent.synthetics?.resultId, fakeResultId)

        // synthetics is diffed — nil in update (unchanged).
        let update = try XCTUnwrap(writer.events(ofType: RUMViewUpdateEvent.self).first)
        XCTAssertEqual(update.session.type, .synthetics)
        XCTAssertNil(update.synthetics)
    }

    func testWhenViewIsStopped_itMakesAttributesImmutable() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let initialAttributes = ["key1": "value1", "key2": "value2"]
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewName",
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: initialAttributes, identity: .mockViewIdentifier()),
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
            )
        )
        XCTAssertFalse(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(attributes: ["additionalFoo": "additionalBar"]),
                context: context,
                writer: writer
            ),
            "The command should be ignored."
        )

        // Full view events always carry context.
        writer.events(ofType: RUMViewEvent.self).forEach {
            XCTAssertEqual($0.context?.contextInfo as? [String: String], initialAttributes)
        }
        // Update events diff context — unchanged between full event and stop → nil.
        writer.events(ofType: RUMViewUpdateEvent.self).forEach {
            XCTAssertNil($0.context)
        }
    }

    func testGivenMultipleViewScopes_eachScopeUsesUniqueViewID() throws {
        func createScope(uri: String, name: String) -> RUMViewScope {
            RUMViewScope(
                isInitialView: false,
                parent: parent,
                dependencies: .mockWith(featureFlags: ff),
                identity: .mockViewIdentifier(),
                path: uri,
                name: name,
                customTimings: [:],
                startTime: .mockAny(),
                serverTimeOffset: .zero,
                interactionToNextViewMetric: INVMetricMock(),
                viewIndexInSession: 1
            )
        }

        let scope1 = createScope(uri: "View1URL", name: "View1Name")
        let scope2 = createScope(uri: "View2URL", name: "View2Name")

        [scope1, scope2].forEach { scope in
            _ = scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
            _ = scope.process(command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        }

        // Each scope: 1 full event + 1 update event.
        let view1Full = writer.events(ofType: RUMViewEvent.self).filter { $0.view.url == "View1URL" }
        let view2Full = writer.events(ofType: RUMViewEvent.self).filter { $0.view.url == "View2URL" }
        let view1Updates = writer.events(ofType: RUMViewUpdateEvent.self).filter { $0.view.url == "View1URL" }
        let view2Updates = writer.events(ofType: RUMViewUpdateEvent.self).filter { $0.view.url == "View2URL" }

        XCTAssertEqual(view1Full.count + view1Updates.count, 2)
        XCTAssertEqual(view2Full.count + view2Updates.count, 2)

        // view.id is always forwarded — same across full and update for the same scope.
        XCTAssertEqual(view1Full[0].view.id, view1Updates[0].view.id)
        XCTAssertEqual(view2Full[0].view.id, view2Updates[0].view.id)
        XCTAssertNotEqual(view1Full[0].view.id, view2Full[0].view.id)
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
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: processLaunchDate,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

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

        // dd.session.sessionPrecondition is always forwarded in both event types.
        XCTAssertGreaterThan(totalViewEventCount, 1)
        writer.events(ofType: RUMViewEvent.self).forEach {
            XCTAssertEqual($0.dd.session?.sessionPrecondition, randomPrecondition)
        }
        writer.events(ofType: RUMViewUpdateEvent.self).forEach {
            XCTAssertEqual($0.dd.session?.sessionPrecondition, randomPrecondition)
        }
    }

    // MARK: - Feature Flags (RUM feature flags, not .viewUpdates)

    func testGivenActiveView_whenFeatureFlagEvaluated_itAddsTheFeatureFlag() throws {
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: .mockDecember15th2019At10AMUTC(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        )
        let featureFlagCommand = RUMAddFeatureFlagEvaluationCommand.mockRandom()
        XCTAssertTrue(
            scope.process(command: featureFlagCommand, context: context, writer: writer)
        )

        // First write: full event with empty feature flags.
        let fullEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(fullEvents.count, 1)
        let initialFlags = try XCTUnwrap(fullEvents[0].featureFlags)
        XCTAssertEqual(initialFlags.featureFlagsInfo.count, 0)

        // Second write: delta update — featureFlags always forwarded.
        let updateEvents = writer.events(ofType: RUMViewUpdateEvent.self)
        XCTAssertEqual(updateEvents.count, 1)
        let updatedFlags = try XCTUnwrap(updateEvents[0].featureFlags)
        XCTAssertEqual(updatedFlags.featureFlagsInfo.count, 1)
        XCTAssertEqual(updatedFlags.featureFlagsInfo[featureFlagCommand.name] as! String, featureFlagCommand.value as! String)
    }

    func testGivenActiveView_whenFeatureFlagReEvaluated_itModifiesTheFeatureFlag() throws {
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: .mockDecember15th2019At10AMUTC(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        )
        let flagName: String = .mockRandom()
        let flagFinalValue: String = .mockRandom()

        XCTAssertTrue(scope.process(command: RUMAddFeatureFlagEvaluationCommand.mockWith(name: flagName), context: context, writer: writer))
        XCTAssertTrue(scope.process(command: RUMAddFeatureFlagEvaluationCommand.mockWith(name: flagName, value: flagFinalValue), context: context, writer: writer))

        XCTAssertEqual(totalViewEventCount, 3)
        // Last update event has the final flag value (featureFlags always forwarded).
        let lastUpdateFlags = try XCTUnwrap(writer.events(ofType: RUMViewUpdateEvent.self).last?.featureFlags)
        XCTAssertEqual(lastUpdateFlags.featureFlagsInfo.count, 1)
        XCTAssertEqual(lastUpdateFlags.featureFlagsInfo[flagName] as! String, flagFinalValue)
    }

    // MARK: - Periodic Full View Event Resync

    func testWhenConsecutiveUpdatesReachTheLimit_itResendsAFullViewEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

        // First write is a full event and becomes the baseline (consecutiveViewUpdatesCount == 0).
        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()), context: context, writer: writer))

        // Send `maxConsecutiveViewUpdates` updates — all deltas against the baseline.
        for index in 0..<RUMViewScope.Constants.maxConsecutiveViewUpdates {
            currentTime.addTimeInterval(1)
            _ = scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-\(index)"),
                context: context,
                writer: writer
            )
        }

        XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).count, 1, "Only the initial write should be a full event so far")
        XCTAssertEqual(
            writer.events(ofType: RUMViewUpdateEvent.self).count,
            Int(RUMViewScope.Constants.maxConsecutiveViewUpdates),
            "Every update up to the limit should be sent as a delta"
        )

        // The next update exceeds the limit — a full event should be resent instead of a delta.
        currentTime.addTimeInterval(1)
        _ = scope.process(
            command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-over-limit"),
            context: context,
            writer: writer
        )

        XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).count, 2, "A full event should be resent once the consecutive update limit is reached")
        XCTAssertEqual(
            writer.events(ofType: RUMViewUpdateEvent.self).count,
            Int(RUMViewScope.Constants.maxConsecutiveViewUpdates),
            "The resync write must not also be counted as a delta"
        )

        // The following write should be a delta again, as the counter was reset by the resync.
        currentTime.addTimeInterval(1)
        _ = scope.process(
            command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-resync"),
            context: context,
            writer: writer
        )

        XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).count, 2, "No extra full event expected right after a resync")
        XCTAssertEqual(
            writer.events(ofType: RUMViewUpdateEvent.self).count,
            Int(RUMViewScope.Constants.maxConsecutiveViewUpdates) + 1,
            "The write right after a resync should be a delta again"
        )
    }

    func testWhenViewUpdatesIsEnabled_everyFullEventIsMarkedAsDeltaBaseline() throws {
        // Every full `RUMViewEvent` written under `.viewUpdates` — the initial baseline and any later
        // resync — must be marked `isDeltaBaseline` so `RUMViewEventsFilter` never collapses it as
        // redundant, since deltas in the same upload batch may be diffed against it.
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()), context: context, writer: writer))

        for index in 0..<RUMViewScope.Constants.maxConsecutiveViewUpdates {
            currentTime.addTimeInterval(1)
            _ = scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-\(index)"),
                context: context,
                writer: writer
            )
        }

        // Triggers the resync (second full event).
        currentTime.addTimeInterval(1)
        _ = scope.process(
            command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-over-limit"),
            context: context,
            writer: writer
        )

        let fullEventMetadata = writer.metadata(ofType: RUMViewEvent.Metadata.self)
        XCTAssertEqual(fullEventMetadata.count, 2, "Both the initial baseline and the resync should carry metadata")
        XCTAssertTrue(fullEventMetadata.allSatisfy { $0.isDeltaBaseline == true }, "All full events under viewUpdates must be marked as delta baselines")
    }

    // MARK: - Custom Timings

    func testGivenActiveView_whenCustomTimingIsRegistered_itSendsUpdateEvents() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )
        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer))

        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(scope.process(command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-500000000ns"), context: context, writer: writer))

        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(scope.process(command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-1000000000ns"), context: context, writer: writer))

        XCTAssertEqual(totalViewEventCount, 3)

        // First write: full event — empty timings.
        let fullEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(fullEvent.view.customTimings?.customTimingsInfo, [:])

        // Update events — customTimings is diffed, present when it changes.
        let updates = writer.events(ofType: RUMViewUpdateEvent.self)
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].view.customTimings?.customTimingsInfo, ["timing-after-500000000ns": 500_000_000])
        XCTAssertEqual(
            updates[1].view.customTimings?.customTimingsInfo,
            ["timing-after-500000000ns": 500_000_000, "timing-after-1000000000ns": 1_000_000_000]
        )
    }

    func testGivenInactiveView_whenCustomTimingIsRegistered_itDoesNotSendUpdateEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )
        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer))
        XCTAssertFalse(scope.process(command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer))

        let countBefore = totalViewEventCount
        currentTime.addTimeInterval(0.5)
        _ = scope.process(command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-500000000ns"), context: context, writer: writer)

        XCTAssertEqual(totalViewEventCount, countBefore, "No new event expected for inactive view")
        // The last full event has empty customTimings (stop view had no timings).
        let stopUpdateEvent = try XCTUnwrap(writer.events(ofType: RUMViewUpdateEvent.self).last)
        XCTAssertNil(stopUpdateEvent.view.customTimings)
    }

    // MARK: - View Hitches

    func testWhenThereAreHitches_firstFullEventContainsSlowFrames_updatesDoNot() {
        var hitches: [Hitch] = []
        (0...Int.mockRandom(min: 1, max: 10)).forEach {
            hitches.append((start: TimeInterval($0).dd.toInt64Nanoseconds, duration: 0.016.dd.toInt64Nanoseconds))
        }
        let hitchesDuration = TimeInterval.ddFromNanoseconds(hitches.map { $0.duration }.reduce(0, +))
        let viewHitchesReaderFactory = { ViewHitchesMock(hitchesDataModel: (hitches: hitches, hitchesDuration: hitchesDuration)) }
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(viewHitchesReaderFactory: viewHitchesReaderFactory, featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockRandom(),
            name: .mockRandom(),
            customTimings: [:],
            startTime: .mockAny(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: nil,
            viewIndexInSession: 1
        )

        _ = scope.process(command: RUMStartViewCommand.mockWith(), context: context, writer: writer)
        _ = scope.process(command: RUMAddViewTimingCommand.mockAny(), context: context, writer: writer)
        _ = scope.process(command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"), context: context, writer: writer)
        _ = scope.process(command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2"), context: context, writer: writer)
        _ = scope.process(command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"), context: context, writer: writer)
        _ = scope.process(command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2"), context: context, writer: writer)
        _ = scope.process(command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(), context: context, writer: writer)
        _ = scope.process(command: RUMStopViewCommand.mockAny(), context: context, writer: writer)

        XCTAssertEqual(totalViewEventCount, 6)

        // First full event carries the slow frames.
        XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).first?.view.slowFrames?.count, hitches.count)

        // Update events have nil slowFrames (unchanged between snapshots → diffed out).
        writer.events(ofType: RUMViewUpdateEvent.self).forEach {
            XCTAssertNil($0.view.slowFrames, "slowFrames should be nil in update events when unchanged")
        }
    }

    func testWhenThereAreViewHitches_stopViewUpdateEventHasSlowFramesRate() {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        var hitches: [Hitch] = []
        (0..<10).forEach {
            hitches.append((start: TimeInterval($0).dd.toInt64Nanoseconds, duration: 0.016.dd.toInt64Nanoseconds))
        }
        let hitchesDuration = TimeInterval.ddFromNanoseconds(hitches.map { $0.duration }.reduce(0, +))
        let viewHitchesReaderFactory = { ViewHitchesMock(hitchesDataModel: (hitches: hitches, hitchesDuration: hitchesDuration)) }
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(viewHitchesReaderFactory: viewHitchesReaderFactory, featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockRandom(),
            name: .mockRandom(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: nil,
            viewIndexInSession: 1
        )

        _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentTime), context: context, writer: writer)
        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMAddViewTimingCommand.mockWith(time: currentTime), context: context, writer: writer)
        currentTime.addTimeInterval(9)
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: currentTime), context: context, writer: writer)

        XCTAssertEqual(totalViewEventCount, 3)

        // slowFramesRate is diffed — nil until it changes (only computed at stop).
        let updates = writer.events(ofType: RUMViewUpdateEvent.self)
        XCTAssertNil(updates.first?.view.slowFramesRate,  "Intermediate update: no rate yet")
        XCTAssertEqual(updates.last?.view.slowFramesRate, 16, "Stop update: rate is computed")
    }

    func testWhenThereAreAppHangs_stopViewUpdateEventHasFreezeRate() {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(hasAppHangsEnabled: true, featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockRandom(),
            name: .mockRandom(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: nil,
            viewIndexInSession: 1
        )

        _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentTime), context: context, writer: writer)
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
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: currentTime), context: context, writer: writer)

        XCTAssertEqual(totalViewEventCount, 3)

        // freezeRate is diffed — nil until computed at stop.
        let updates = writer.events(ofType: RUMViewUpdateEvent.self)
        XCTAssertNil(updates.first?.view.freezeRate,          "Intermediate update: no rate yet")
        XCTAssertEqual(updates.last?.view.freezeRate, 0.5.hours, "Stop update: rate is computed")
    }

    // MARK: - Count Correction

    func testGivenDroppedEvents_countsAreAdjustedInUpdateEvents() throws {
        struct ResourceMapperHolder { var resourceEventMapper: RUM.ResourceEventMapper? }
        var resourceMapperHolder = ResourceMapperHolder()

        let eventBuilder = RUMEventBuilder(
            eventsMapper: .mockWith(
                errorEventMapper: { _ in nil },
                resourceEventMapper: { resourceMapperHolder.resourceEventMapper?($0) },
                actionEventMapper: { _ in nil }
            )
        )
        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: .mockWith(eventBuilder: eventBuilder, featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewController",
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )
        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer))
        XCTAssertTrue(scope.process(command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"), context: context, writer: writer))
        XCTAssertTrue(scope.process(command: RUMAddUserActionCommand.mockAny(), context: context, writer: writer))
        XCTAssertTrue(scope.process(command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(), context: context, writer: writer))
        XCTAssertTrue(scope.process(command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2"), context: context, writer: writer))

        let resourceScope1 = try XCTUnwrap(scope.resourceScopes["/resource/1"])
        let resourceID1 = resourceScope1.resourceUUID.toRUMDataFormat
        resourceMapperHolder.resourceEventMapper = { event in event.resource.id == resourceID1 ? nil : event }

        XCTAssertTrue(scope.process(command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/2"), context: context, writer: writer))
        XCTAssertTrue(scope.process(command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"), context: context, writer: writer))
        XCTAssertFalse(scope.process(command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer))

        XCTAssertEqual(totalViewEventCount, 4)

        // The stop-view update event reflects the final accumulated counts.
        // resource: 1 (1 dropped), action: 0 (dropped), error: 0 (dropped).
        // Find the update that carries the resource count change (resource2 completion).
        let resourceCountUpdate = try XCTUnwrap(
            writer.events(ofType: RUMViewUpdateEvent.self).last(where: { $0.view.resource != nil })
        )
        XCTAssertEqual(resourceCountUpdate.view.resource?.count, 1, "After dropping 1 Resource event (of 2), View should record 1 Resource")

        // Action and error counts were dropped so never changed from 0 — nil in all update events.
        writer.events(ofType: RUMViewUpdateEvent.self).forEach {
            XCTAssertNil($0.view.action, "Action was dropped — count never changed from 0")
            XCTAssertNil($0.view.error,  "Error was dropped — count never changed from 0")
        }

        // dd.documentVersion increments on each write.
        let lastUpdate = try XCTUnwrap(writer.events(ofType: RUMViewUpdateEvent.self).last)
        XCTAssertEqual(lastUpdate.dd.documentVersion, 4)
    }

    // MARK: - Has Replay

    func testViewUpdate_onceHasReplayIsTrueItRemainsTrue() throws {
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: false))

        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer))

        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: true))
        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(scope.process(command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "t1"), context: context, writer: writer))

        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: false))
        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(scope.process(command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "t2"), context: context, writer: writer))

        XCTAssertEqual(totalViewEventCount, 3)

        // session.hasReplay is always forwarded in update events.
        let fullEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(fullEvent.session.hasReplay, false)

        let updates = writer.events(ofType: RUMViewUpdateEvent.self)
        XCTAssertEqual(updates[0].session.hasReplay, true)   // became true
        XCTAssertEqual(updates[1].session.hasReplay, true)   // stays true once set
    }

    // MARK: - Fatal Error Context

    func testWhenViewIsStarted_itUpdatesFatalErrorContextWithView() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(featureScope: featureScope, fatalErrorContext: fatalErrorContext, featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "ViewController",
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

        featureScope.eventWriteContext { context, writer in
            _ = scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        }

        let rumViewWritten = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let rumViewInFatalErrorContext = try XCTUnwrap(fatalErrorContext.view)
        DDAssertReflectionEqual(rumViewWritten, rumViewInFatalErrorContext)
    }

    // MARK: - Accessibility

    @available(iOS 13.0, tvOS 13.0, *)
    func testAccessibilityDelta_onlyChangedFieldsAreSentInUpdate() throws {
        // Given
        let reader = AccessibilityReaderMock(state: AccessibilityInfo(
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
        ))
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockWith(accessibilityReader: reader, featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "MyView",
            customTimings: [:],
            startTime: .mockDecember15th2019At10AMUTC(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: scope.identity), context: context, writer: writer)

        // When — only screenReaderEnabled changes
        reader.state = AccessibilityInfo(
            textSize: "medium",
            screenReaderEnabled: true,
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
        _ = scope.process(command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(), context: context, writer: writer)

        // Then — update carries only the changed field
        let update = try XCTUnwrap(writer.events(ofType: RUMViewUpdateEvent.self).first)
        let accessibility = try XCTUnwrap(update.view.accessibility)
        XCTAssertEqual(accessibility.screenReaderEnabled, true, "Changed field should be present")
        XCTAssertNil(accessibility.boldTextEnabled, "Unchanged field should be nil (no change)")
        XCTAssertNil(accessibility.textSize, "Unchanged field should be nil (no change)")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testAccessibilityDelta_noUpdateWhenNothingChanges() throws {
        // Given
        let reader = AccessibilityReaderMock(state: AccessibilityInfo(
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
        ))
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockWith(accessibilityReader: reader, featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: "UIViewController",
            name: "MyView",
            customTimings: [:],
            startTime: .mockDecember15th2019At10AMUTC(),
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: scope.identity), context: context, writer: writer)

        // When — accessibility state unchanged
        _ = scope.process(command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(), context: context, writer: writer)

        // Then — update carries no accessibility field
        let update = try XCTUnwrap(writer.events(ofType: RUMViewUpdateEvent.self).first)
        XCTAssertNil(update.view.accessibility, "Accessibility should be nil when nothing changed")
    }

    // MARK: - Baseline Promotion

    func testInitialView_firstEventIsNotStoredAsBaseline_secondEventIsAlsoFull() throws {
        // The very first event of the initial view has timeSpent = 1ns (floored to minimumTimeSpent when
        // command.time == viewStartTime). RUMViewEventsFilter discards that event on the backend, so it
        // must NOT be stored as baseline — otherwise the second event would be diffed against a dropped event.
        // Expected sequence: full, full, delta.
        let startTime: Date = .mockDecember15th2019At10AMUTC()
        var currentTime = startTime
        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 0
        )

        // First command at t=0 → timeSpent = 1ns placeholder, written as full event, NOT stored as baseline.
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()), context: context, writer: writer)

        // Second command at t>0 → timeSpent > 1ns, no baseline yet → written as full event, stored as baseline.
        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime), context: context, writer: writer)

        // Third command at t>0 → baseline is set → written as delta.
        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()), context: context, writer: writer)

        XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).count, 2, "First two writes must be full events")
        XCTAssertEqual(writer.events(ofType: RUMViewUpdateEvent.self).count, 1, "Only the third write is a delta")
    }

    func testSubsequentView_firstEventIsStoredAsBaseline_secondEventIsDelta() throws {
        // Subsequent views (viewIndexInSession > 0) never write a 1ns placeholder — they always start with
        // a real duration. Their first written event must be stored as baseline immediately so the second
        // write is a delta.
        let startTime: Date = .mockDecember15th2019At10AMUTC()
        var currentTime = startTime
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockWith(featureFlags: ff),
            identity: .mockViewIdentifier(),
            path: .mockAny(),
            name: .mockAny(),
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero,
            interactionToNextViewMetric: INVMetricMock(),
            viewIndexInSession: 1
        )

        // First command at t>0 → timeSpent > 1ns, stored as baseline immediately.
        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()), context: context, writer: writer)

        // Second command → delta.
        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()), context: context, writer: writer)

        XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).count, 1, "First write must be a full event")
        XCTAssertEqual(writer.events(ofType: RUMViewUpdateEvent.self).count, 1, "Second write must be a delta")
    }
}
