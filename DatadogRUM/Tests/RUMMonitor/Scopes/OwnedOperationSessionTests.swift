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
        func isOperationSessionActive(start: Date, lastInteraction: Date) -> Bool { true }
    }

    private final class Fixture {
        let feature = OriginalFeature()
        let core: SingleFeatureCoreMock<OriginalFeature>
        let origin: RUMOperationOrigin
        let session: RUMSessionScope
        let scope = FeatureScopeMock()
        let writer = FileWriterMock()
        let context = DatadogContext.mockAny()
        let date = Date()
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
                initialSessionUUID: base.initialSessionUUID, timeseriesCollector: base.timeseriesCollector,
                operationOrigin: origin
            )
            session = .mockWith(startTime: date, dependencies: dependencies)
            origin.setSession(session.sessionUUID.toRUMDataFormat)
            origin.updateSession(session.sessionUUID.toRUMDataFormat, start: date, lastInteraction: date)
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
        XCTAssertFalse(initial.isValid, "Session dates have not been initialized")
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
}
