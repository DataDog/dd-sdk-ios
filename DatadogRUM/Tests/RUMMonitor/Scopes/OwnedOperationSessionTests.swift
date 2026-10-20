/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal) @testable import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

final class OwnedOperationSessionTests: XCTestCase {
    private final class OriginalFeature: DatadogFeature, RUMOperationOriginProviding {
        static let name = "rum"
        let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
        var operationOrigin: RUMOperationOrigin?
        let monitor = NSObject()
        func isOperationMonitor(_ monitor: AnyObject) -> Bool { self.monitor === monitor }
        func isOperationSessionActive(start: TimeInterval, lastInteraction: TimeInterval) -> Bool { true }
    }

    private final class Fixture {
        let feature = OriginalFeature()
        let core: SingleFeatureCoreMock<OriginalFeature>
        let origin: RUMOperationOrigin
        let session: RUMSessionScope
        let parent = RUMContextProviderMock()
        let scope = FeatureScopeMock()
        let writer = FileWriterMock()
        let context = DatadogContext.mockAny()
        let date = Date()
        let clock = MonotonicClockMock()
        init() {
            core = SingleFeatureCoreMock(feature: feature)
            origin = RUMOperationOrigin(core: core, owner: RUMContextHandoff.Owner())
            feature.operationOrigin = origin
            origin.attach(feature: feature, monitor: feature.monitor)
            let base = RUMScopeDependencies.mockWith(featureScope: scope, samplingRate: 100,
                                                     featureFlags: [.multiSceneTracking: true])
            let dependencies = RUMScopeDependencies(
                featureScope: base.featureScope, rumApplicationID: base.rumApplicationID,
                samplingRate: base.samplingRate, trackBackgroundEvents: base.trackBackgroundEvents,
                trackFrustrations: base.trackFrustrations, hasAppHangsEnabled: base.hasAppHangsEnabled,
                firstPartyHosts: base.firstPartyHosts, distributedTracingSampleRate: base.distributedTracingSampleRate,
                eventBuilder: base.eventBuilder, rumUUIDGenerator: base.rumUUIDGenerator,
                backtraceReporter: base.backtraceReporter, ciTest: base.ciTest, syntheticsTest: base.syntheticsTest,
                renderLoopObserver: base.renderLoopObserver, firstFrameReader: base.firstFrameReader,
                viewHitchesReaderFactory: base.viewHitchesReaderFactory, vitalsReaders: base.vitalsReaders,
                accessibilityReader: base.accessibilityReader, onSessionUpdate: base.onSessionUpdate,
                viewCache: base.viewCache, fatalErrorContext: base.fatalErrorContext,
                sessionEndedMetric: base.sessionEndedMetric, viewEndedMetricFactory: base.viewEndedMetricFactory,
                appStateManager: base.appStateManager, watchdogTermination: base.watchdogTermination,
                featureFlags: base.featureFlags, networkSettledMetricFactory: base.networkSettledMetricFactory,
                interactionToNextViewMetricFactory: base.interactionToNextViewMetricFactory, sessionType: base.sessionType,
                monotonicClock: clock, initialSessionUUID: base.initialSessionUUID, timeseriesCollector: base.timeseriesCollector,
                operationOrigin: origin
            )
            session = .mockWith(parent: parent, startTime: date, dependencies: dependencies)
            origin.setSession(session.sessionUUID.toRUMDataFormat)
            origin.updateSession(session.sessionUUID.toRUMDataFormat, start: session.sessionStart, lastInteraction: session.lastInteraction)
        }
        func command(capture: RUMContextHandoff.CurrentValue?, step: RUMVitalOperationStepEvent.Vital.StepType = .end) -> RUMOwnedOperationStepCommand {
            let legacy = RUMOperationStepVitalCommand.mockWith(vitalId: "owned-step", name: "checkout",
                                                               stepType: step, time: date)
            return RUMOwnedOperationStepCommand(step: legacy, origin: origin, capture: capture)
        }
        var ownedMessages: [OwnedOperationMessage] {
            scope.messagesSent().compactMap {
                if case .payload(let value) = $0 { return value as? OwnedOperationMessage }
                return nil
            }
        }
    }

    func testProvedSessionWithoutResolvableViewEmitsNullViewAndNoBorrowedAction() throws {
        let fixture = Fixture()
        let sessionID = try XCTUnwrap(UUID(uuidString: fixture.session.sessionUUID.toRUMDataFormat))
        let original = RUMCoreContext.mockWith(sessionID: sessionID, viewID: "removed", userActionID: "old-action")
        let capture = RUMContextHandoff.CurrentValue(rumContext: original, sceneIdentifier: "original",
                            hasPendingUserAction: false, excludedUserActionID: nil)
        fixture.session.processOwnedOperation(fixture.command(capture: capture), context: fixture.context, writer: fixture.writer)
        let event = try XCTUnwrap(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).first)
        XCTAssertEqual(event.session.id, fixture.session.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(event.view.id, RUMUUID.nullUUID.toRUMDataFormat)
        let message = try XCTUnwrap(fixture.ownedMessages.first)
        XCTAssertNil(message.attributes[RUMCoreContext.IDs.viewID])
        XCTAssertNil(message.attributes[RUMCoreContext.IDs.userActionID])
        XCTAssertEqual(fixture.session.viewScopes.count, 0)
    }

    func testAuthoritativeAbsentSessionRefusesBeforeManagerAndWriter() {
        let fixture = Fixture()
        let capture = RUMContextHandoff.CurrentValue(rumContext: nil, sceneIdentifier: "original",
                            hasPendingUserAction: false, excludedUserActionID: nil)
        fixture.session.processOwnedOperation(fixture.command(capture: capture), context: fixture.context, writer: fixture.writer)
        XCTAssertTrue(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).isEmpty)
        XCTAssertTrue(fixture.ownedMessages.isEmpty)
    }

    func testCapturedOldSessionCannotAttachToFreshSessionOrCreateAView() {
        let fixture = Fixture()
        let capture = RUMContextHandoff.CurrentValue(rumContext: .mockWith(sessionID: UUID(), viewID: "original"),
                            sceneIdentifier: "original", hasPendingUserAction: false, excludedUserActionID: nil)
        fixture.session.processOwnedOperation(fixture.command(capture: capture), context: fixture.context, writer: fixture.writer)
        XCTAssertTrue(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).isEmpty)
        XCTAssertTrue(fixture.ownedMessages.isEmpty)
        XCTAssertTrue(fixture.session.viewScopes.isEmpty)
    }

    func testSourceLessFirstOperationInitializesOriginalSessionTiming() throws {
        let fixture = Fixture()
        let sessionID = fixture.session.sessionUUID.toRUMDataFormat
        fixture.origin.setSession(nil)
        fixture.origin.setSession(sessionID)
        let initial = try XCTUnwrap(fixture.origin.ownership(for: sessionID))
        XCTAssertFalse(initial.isValid, "Session clock readings have not been initialized")
        XCTAssertTrue(fixture.session.process(command: fixture.command(capture: nil),
                                             context: fixture.context, writer: fixture.writer))
        XCTAssertTrue(initial.isValid)
        XCTAssertEqual(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).count, 1)
        XCTAssertEqual(fixture.ownedMessages.count, 1)
    }

    func testUpdateAndRetryProduceEventsWithoutProfilerEnvelopes() {
        let fixture = Fixture()
        for step in [RUMVitalOperationStepEvent.Vital.StepType.update, .retry] {
            fixture.session.processOwnedOperation(fixture.command(capture: nil, step: step),
                                                  context: fixture.context, writer: fixture.writer)
        }
        XCTAssertEqual(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).count, 2)
        XCTAssertTrue(fixture.ownedMessages.isEmpty)
    }

    func testCapturedStoppedViewKeepsRetainedOwnerOrNullWithoutBorrowingPeer() throws {
        for retainsOriginal in [false, true] {
            let fixture = Fixture()
            let targetA = RUMCommandTarget.scene(.init(rawValue: "original"))
            let targetB = RUMCommandTarget.scene(.init(rawValue: "peer"))
            let start = RUMStartViewCommand(
                time: fixture.date, identity: ViewIdentifier("original"),
                name: "original", path: "original", globalAttributes: [:], attributes: [:],
                instrumentationType: .manual, target: targetA
            )
            _ = fixture.session.process(command: start, context: fixture.context, writer: fixture.writer)
            let original = try XCTUnwrap(fixture.session.viewScopes.first { $0.viewName == "original" })
            let sessionID = try XCTUnwrap(UUID(uuidString: fixture.session.sessionUUID.toRUMDataFormat))
            let selected = RUMCoreContext.mockWith(
                applicationID: fixture.session.context.rumApplicationID,
                sessionID: sessionID, viewID: original.viewUUID.toRUMDataFormat,
                userActionID: nil, serverTimeOffset: 0, viewPath: original.viewPath,
                viewName: original.viewName
            )
            let capture = RUMContextHandoff.CurrentValue(
                rumContext: selected, sceneIdentifier: "original",
                hasPendingUserAction: false, excludedUserActionID: nil
            )
            if retainsOriginal {
                var resource = RUMStartResourceCommand.mockWith(
                    resourceKey: "keep-original", time: fixture.date.addingTimeInterval(1)
                )
                resource.target = targetA
                _ = fixture.session.process(command: resource, context: fixture.context, writer: fixture.writer)
                XCTAssertEqual(original.resourceScopes.count, 1)
            }
            let peerStart = RUMStartViewCommand(
                time: fixture.date.addingTimeInterval(2), identity: ViewIdentifier("peer"),
                name: "peer", path: "peer", globalAttributes: [:], attributes: [:],
                instrumentationType: .manual, target: targetB
            )
            _ = fixture.session.process(command: peerStart, context: fixture.context, writer: fixture.writer)
            let peer = try XCTUnwrap(fixture.session.viewScopes.first { $0.viewName == "peer" })
            var stop = RUMStopViewCommand.mockWith(
                time: fixture.date.addingTimeInterval(3), identity: ViewIdentifier("original")
            )
            stop.target = targetA
            _ = fixture.session.process(command: stop, context: fixture.context, writer: fixture.writer)
            XCTAssertFalse(original.isActiveView)
            XCTAssertEqual(fixture.session.viewScopes.contains { $0 === original }, retainsOriginal)
            XCTAssertTrue(peer.isActiveView)
            XCTAssertEqual(fixture.session.context.activeViewID, peer.viewUUID)
            var action = RUMStartUserActionCommand.mockWith(
                time: fixture.date.addingTimeInterval(4), name: "peer-action"
            )
            action.target = targetB
            _ = fixture.session.process(command: action, context: fixture.context, writer: fixture.writer)
            let peerAction = try XCTUnwrap(peer.userActionScope)
            XCTAssertNil(original.userActionScope)
            let ownership = try XCTUnwrap(fixture.origin.ownership(for: selected.sessionID))
            XCTAssertTrue(ownership.isValid)
            let viewsBefore = fixture.writer.events(ofType: RUMViewEvent.self).count
            let peerViewsBefore = fixture.writer.events(ofType: RUMViewEvent.self)
                .filter { $0.view.id == peer.viewUUID.toRUMDataFormat }.count
            let retainedScopesBefore = fixture.session.viewScopes.map { ObjectIdentifier($0) }
            let step = RUMOperationStepVitalCommand.mockWith(
                vitalId: "captured-stopped", name: "captured-stopped",
                stepType: .end, time: fixture.date.addingTimeInterval(5)
            )

            fixture.session.processOwnedOperation(
                RUMOwnedOperationStepCommand(step: step, origin: fixture.origin, capture: capture),
                context: fixture.context, writer: fixture.writer
            )

            let event = try XCTUnwrap(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).first)
            XCTAssertEqual(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).count, 1)
            let message = try XCTUnwrap(fixture.ownedMessages.first)
            XCTAssertEqual(fixture.ownedMessages.count, 1)
            XCTAssertEqual(event.session.id, selected.sessionID)
            XCTAssertEqual(event.vital.id, "captured-stopped")
            XCTAssertEqual(message.operation.id, event.vital.id)
            XCTAssertTrue(message.ownership === ownership)
            XCTAssertEqual(message.attributes[RUMCoreContext.IDs.sessionID] as? String, selected.sessionID)
            XCTAssertNil(message.attributes[RUMCoreContext.IDs.userActionID])
            if retainsOriginal {
                XCTAssertEqual(event.view.id, original.viewUUID.toRUMDataFormat)
                XCTAssertEqual(event.view.url, original.viewPath)
                XCTAssertEqual(message.attributes[RUMCoreContext.IDs.viewID] as? [String], [original.viewUUID.toRUMDataFormat])
                XCTAssertEqual(message.attributes[RUMCoreContext.IDs.viewName] as? [String], [original.viewName])
                XCTAssertEqual(original.resourceScopes.count, 1)
            } else {
                XCTAssertEqual(event.view.id, RUMUUID.nullUUID.toRUMDataFormat)
                XCTAssertNil(message.attributes[RUMCoreContext.IDs.viewID])
                XCTAssertNil(message.attributes[RUMCoreContext.IDs.viewName])
            }
            XCTAssertTrue(peer.userActionScope === peerAction)
            XCTAssertTrue(peer.isActiveView)
            XCTAssertEqual(fixture.session.context.activeViewID, peer.viewUUID)
            XCTAssertEqual(fixture.session.viewScopes.map { ObjectIdentifier($0) }, retainedScopesBefore)
            XCTAssertEqual(fixture.writer.events(ofType: RUMViewEvent.self).count, viewsBefore)
            XCTAssertEqual(fixture.writer.events(ofType: RUMViewEvent.self)
                .filter { $0.view.id == peer.viewUUID.toRUMDataFormat }.count, peerViewsBefore)

            let freshStep = RUMOperationStepVitalCommand.mockWith(
                vitalId: "source-less-peer", name: "source-less-peer",
                stepType: .end, time: fixture.date.addingTimeInterval(6)
            )
            fixture.session.processOwnedOperation(
                RUMOwnedOperationStepCommand(step: freshStep, origin: fixture.origin, capture: nil),
                context: fixture.context, writer: fixture.writer
            )
            XCTAssertEqual(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).count, 2)
            XCTAssertEqual(fixture.ownedMessages.count, 2)
            let freshEvent = try XCTUnwrap(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).last)
            let freshMessage = try XCTUnwrap(fixture.ownedMessages.last)
            XCTAssertEqual(freshEvent.view.id, peer.viewUUID.toRUMDataFormat)
            XCTAssertEqual(freshEvent.vital.id, "source-less-peer")
            XCTAssertEqual(freshMessage.attributes[RUMCoreContext.IDs.viewID] as? [String], [peer.viewUUID.toRUMDataFormat])
            XCTAssertEqual(freshMessage.attributes[RUMCoreContext.IDs.userActionID] as? String,
                           peerAction.actionUUID.toRUMDataFormat)
            XCTAssertTrue(freshMessage.ownership === ownership)
        }
    }

    func testOwnedOperationAdmissionUsesCapturedMonotonicTimeInsteadOfEventDate() throws {
        for wallClockShift in [-86_400.0, 86_400.0] {
            let fixture = Fixture()
            var command = fixture.command(capture: nil)
            command.time = fixture.date.addingTimeInterval(wallClockShift)
            fixture.clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration)

            fixture.session.processOwnedOperation(
                command, monotonicTime: 1,
                context: fixture.context, writer: fixture.writer
            )

            XCTAssertTrue(fixture.session.isActive)
            XCTAssertEqual(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).count, 1)
            XCTAssertEqual(fixture.ownedMessages.count, 1)
        }
    }

    func testOwnedOperationRefusesMonotonicExpiryWhileEventDateDoesNotAdvance() {
        for maximumDuration in [false, true] {
            let fixture = Fixture()
            if maximumDuration {
                // Keep inactivity below its limit so this case exercises maximum duration.
                for elapsed in stride(from: 600.0, to: RUMSessionScope.Constants.sessionMaxDuration, by: 600.0) {
                    let interaction = RUMAddUserActionCommand.mockWith(time: fixture.date)
                    XCTAssertTrue(fixture.session.process(
                        command: interaction, monotonicTime: elapsed,
                        context: fixture.context, writer: fixture.writer
                    ))
                }
                fixture.clock.advance(by: RUMSessionScope.Constants.sessionMaxDuration)
                XCTAssertFalse(RUMSessionScope.hasTimedOut(
                    lastInteraction: fixture.session.lastInteraction, now: fixture.clock.elapsedTime
                ))
            } else {
                fixture.clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration)
            }

            fixture.session.processOwnedOperation(
                fixture.command(capture: nil),
                context: fixture.context, writer: fixture.writer
            )

            XCTAssertTrue(fixture.writer.events(ofType: RUMVitalOperationStepEvent.self).isEmpty)
            XCTAssertTrue(fixture.ownedMessages.isEmpty)
        }
    }
}
