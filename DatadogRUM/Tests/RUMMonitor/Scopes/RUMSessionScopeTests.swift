/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

class RUMSessionScopeTests: XCTestCase {
    let context: DatadogContext = .mockAny()
    let writer = FileWriterMock()

    private lazy var parent = RUMApplicationScope(
        dependencies: .mockWith(rumApplicationID: "rum-123")
    )

    private func startViewCommand(
        identity: ViewIdentifier,
        name: String,
        sceneIdentifier: RUMSceneIdentifier,
        attributes: [AttributeKey: AttributeValue] = [:],
        time: Date = Date()
    ) -> RUMStartViewCommand {
        RUMStartViewCommand(
            time: time,
            identity: identity,
            name: name,
            path: name,
            globalAttributes: [:],
            attributes: attributes,
            instrumentationType: .uikit,
            target: .scene(sceneIdentifier)
        )
    }

    func testDefaultContext() {
        let scope: RUMSessionScope = .mockWith(parent: parent)

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertNotEqual(scope.context.sessionID, .nullUUID)
        XCTAssertTrue(scope.context.isSessionActive)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testContextWhenSessionIsRejectedBySampler() {
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            dependencies: .mockWith(samplingRate: 0)
       )

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertFalse(scope.sampler.isSampled)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenSessionExceedsMaxDuration_itGetsClosed() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(samplingRate: .mockRandom())
        )

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))

        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
    }

    func testWhenSessionExpiresWithoutTransferringActiveView_itReleasesViewCachePin() throws {
        let dateProvider = RelativeDateProvider()
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: 1)
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: dateProvider.now,
            dependencies: .mockWith(samplingRate: 100, viewCache: viewCache)
        )
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"),
                name: "View A",
                sceneIdentifier: scene,
                time: dateProvider.now
            ),
            context: context,
            writer: writer
        )
        let viewID = try XCTUnwrap(scope.activeView?.viewUUID.toRUMDataFormat)

        dateProvider.advance(bySeconds: RUMSessionScope.Constants.sessionMaxDuration)
        XCTAssertFalse(
            scope.process(
                command: RUMCommandMock(time: dateProvider.now),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(viewCache.sceneIdentifier(forViewID: viewID), scene)

        dateProvider.advance(bySeconds: 2)
        viewCache.insert(
            id: "replacement-view",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            sceneIdentifier: RUMSceneIdentifier(rawValue: "scene-B")
        )
        XCTAssertNil(viewCache.sceneIdentifier(forViewID: viewID))
    }

    func testWhenSessionIsInactiveForCertainDuration_itGetsClosed() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(samplingRate: .mockRandom())
        )

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))

        // Push time forward by less than the session timeout duration:
        currentTime.addTimeInterval(0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))

        // Push time forward by the session timeout duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
    }

    func testWhenSessionReceivesInteractiveEvent_itStaysAlive() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(samplingRate: .mockRandom())
        )

        for _ in 0...10 {
            // Push time forward by less than the session timeout duration:
            currentTime.addTimeInterval(0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)
            XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime, isUserInteraction: true), context: context, writer: writer))
        }

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
    }

    func testWhenSessionReceivesNonInteractiveEvent_itGetsClosed() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(samplingRate: .mockRandom())
        )

        for _ in 0...8 {
            // Push time forward by less than the session timeout duration:
            currentTime.addTimeInterval(0.1 * RUMSessionScope.Constants.sessionTimeoutDuration)
            XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime, isUserInteraction: false), context: context, writer: writer))
        }

        currentTime.addTimeInterval(0.1 * RUMSessionScope.Constants.sessionTimeoutDuration)
        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
    }

    func testItManagesViewScopeLifecycle() {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        XCTAssertEqual(scope.viewScopes.count, 0)

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        XCTAssertEqual(scope.viewScopes.count, 1)
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        XCTAssertEqual(scope.viewScopes.count, 0)

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        XCTAssertEqual(scope.viewScopes.count, 1)
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    func testGivenSameViewIdentity_whenNavigatingAwayAndBack_itCreatesDistinctRUMViewOccurrences() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let homeIdentity = ViewIdentifier("home")
        let detailIdentity = ViewIdentifier("detail")

        _ = scope.process(
            command: startViewCommand(identity: homeIdentity, name: "Home", sceneIdentifier: scene),
            context: context,
            writer: writer
        )
        let firstHomeViewID = try XCTUnwrap(scope.activeView?.viewUUID)

        var stopHome = RUMStopViewCommand.mockWith(identity: homeIdentity)
        stopHome.target = .scene(scene)
        _ = scope.process(command: stopHome, context: context, writer: writer)
        _ = scope.process(
            command: startViewCommand(identity: detailIdentity, name: "Detail", sceneIdentifier: scene),
            context: context,
            writer: writer
        )
        let detailViewID = try XCTUnwrap(scope.activeView?.viewUUID)

        var stopDetail = RUMStopViewCommand.mockWith(identity: detailIdentity)
        stopDetail.target = .scene(scene)
        _ = scope.process(command: stopDetail, context: context, writer: writer)
        _ = scope.process(
            command: startViewCommand(identity: homeIdentity, name: "Home", sceneIdentifier: scene),
            context: context,
            writer: writer
        )
        let returnedHomeViewID = try XCTUnwrap(scope.activeView?.viewUUID)

        XCTAssertEqual(Set([firstHomeViewID, detailViewID, returnedHomeViewID]).count, 3)
        XCTAssertNotEqual(firstHomeViewID, returnedHomeViewID)
    }

    func testGivenFirstOccurrenceHasPendingResource_whenSameIdentityReturns_itKeepsOccurrencesIsolated() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let homeIdentity = ViewIdentifier("home")
        let detailIdentity = ViewIdentifier("detail")
        let resourceKey = "home-1-resource"

        _ = scope.process(
            command: startViewCommand(
                identity: homeIdentity,
                name: "Home",
                sceneIdentifier: scene,
                attributes: ["occurrence": "home-1"]
            ),
            context: context,
            writer: writer
        )
        let firstHomeViewID = try XCTUnwrap(scope.activeView?.viewUUID)
        let firstHomeScope = try XCTUnwrap(scope.activeView)

        var startResource = RUMStartResourceCommand.mockWith(resourceKey: resourceKey)
        startResource.target = .view(firstHomeViewID)
        _ = scope.process(command: startResource, context: context, writer: writer)

        var stopHome = RUMStopViewCommand.mockWith(identity: homeIdentity)
        stopHome.target = .scene(scene)
        _ = scope.process(command: stopHome, context: context, writer: writer)
        _ = scope.process(
            command: startViewCommand(identity: detailIdentity, name: "Detail", sceneIdentifier: scene),
            context: context,
            writer: writer
        )
        let detailViewID = try XCTUnwrap(scope.activeView?.viewUUID)

        let firstHomeEventCountBeforeLateStop = writer.events(ofType: RUMViewEvent.self).filter {
            $0.view.id == firstHomeViewID.toRUMDataFormat
        }.count + writer.events(ofType: RUMViewUpdateEvent.self).filter {
            $0.view.id == firstHomeViewID.toRUMDataFormat
        }.count
        var lateStopHome = RUMStopViewCommand.mockWith(
            attributes: ["occurrence": "late-stop"],
            identity: homeIdentity
        )
        lateStopHome.target = .scene(scene)
        _ = scope.process(command: lateStopHome, context: context, writer: writer)
        let firstHomeEventCountAfterLateStop = writer.events(ofType: RUMViewEvent.self).filter {
            $0.view.id == firstHomeViewID.toRUMDataFormat
        }.count + writer.events(ofType: RUMViewUpdateEvent.self).filter {
            $0.view.id == firstHomeViewID.toRUMDataFormat
        }.count
        XCTAssertEqual(firstHomeEventCountAfterLateStop, firstHomeEventCountBeforeLateStop)
        XCTAssertEqual(firstHomeScope.attributes["occurrence"] as? String, "home-1")

        var stopDetail = RUMStopViewCommand.mockWith(identity: detailIdentity)
        stopDetail.target = .scene(scene)
        _ = scope.process(command: stopDetail, context: context, writer: writer)
        _ = scope.process(
            command: startViewCommand(
                identity: homeIdentity,
                name: "Home",
                sceneIdentifier: scene,
                attributes: ["occurrence": "home-2"]
            ),
            context: context,
            writer: writer
        )
        let returnedHomeViewID = try XCTUnwrap(scope.activeView?.viewUUID)
        let returnedHomeScope = try XCTUnwrap(scope.activeView)

        XCTAssertTrue(scope.viewScopes.contains { $0 === firstHomeScope })
        XCTAssertEqual(firstHomeScope.attributes["occurrence"] as? String, "home-1")
        XCTAssertEqual(returnedHomeScope.attributes["occurrence"] as? String, "home-2")
        XCTAssertEqual(scope.viewScopes.filter(\.isActiveView).count, 1)

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .custom,
                name: "post-pop",
                target: .scene(scene)
            ),
            context: context,
            writer: writer
        )

        var stopResource = RUMStopResourceCommand.mockWith(resourceKey: resourceKey)
        stopResource.target = .view(firstHomeViewID)
        _ = scope.process(command: stopResource, context: context, writer: writer)

        XCTAssertEqual(Set([firstHomeViewID, detailViewID, returnedHomeViewID]).count, 3)
        XCTAssertFalse(scope.viewScopes.contains { $0 === firstHomeScope })
        XCTAssertEqual(scope.viewScopes.filter(\.isActiveView).count, 1)
        XCTAssertTrue(scope.activeView === returnedHomeScope)

        let firstHomeEvents = writer.events(ofType: RUMViewEvent.self).filter {
            $0.view.id == firstHomeViewID.toRUMDataFormat
        }
        XCTAssertFalse(firstHomeEvents.isEmpty)
        XCTAssertTrue(firstHomeEvents.allSatisfy {
            ($0.context?.contextInfo["occurrence"] as? String) == "home-1"
        })

        let resource = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).last)
        XCTAssertEqual(resource.view.id, firstHomeViewID.toRUMDataFormat)
        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(action.view.id, returnedHomeViewID.toRUMDataFormat)
    }

    func testGivenRestoredActiveView_whenSameIdentityStarts_itKeepsOnlyLatestOccurrenceActive() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let identity = ViewIdentifier("home")
        let restoredSource: RUMViewScope = .mockWith(
            parent: parent,
            identity: identity,
            path: "Home",
            name: "Home",
            sceneIdentifier: scene
        )
        let scope = RUMSessionScope(
            isInitialSession: false,
            parent: parent,
            startTime: Date(),
            startPrecondition: .maxDuration,
            context: context,
            dependencies: .mockWith(samplingRate: 100),
            applicationState: .mockAny(),
            resumingViewScopes: [restoredSource]
        )
        let restoredOccurrenceID = try XCTUnwrap(scope.activeView?.viewUUID)

        _ = scope.process(
            command: startViewCommand(
                identity: identity,
                name: "Home",
                sceneIdentifier: scene
            ),
            context: context,
            writer: writer
        )

        let activeViews = scope.viewScopes.filter(\.isActiveView)
        XCTAssertEqual(activeViews.count, 1)
        XCTAssertEqual(scope.viewScopes.count, 1)
        XCTAssertEqual(activeViews.first?.identity, identity)
        XCTAssertNotEqual(activeViews.first?.viewUUID, restoredOccurrenceID)
    }

    func testWhenViewsStartInDifferentScenes_itKeepsBothViewsActive() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )

        XCTAssertEqual(scope.viewScopes.count, 2)
        XCTAssertEqual(scope.viewScopes.filter(\.isActiveView).count, 2)
        XCTAssertEqual(Set(scope.viewScopes.compactMap(\.sceneIdentifier)), Set([sceneA, sceneB]))
        XCTAssertEqual(scope.activeView?.sceneIdentifier, sceneB)
    }

    func testGivenConcurrentScenes_whenNonRepresentativeViewUpdates_watchdogKeepsRepresentativeView() throws {
        let featureScope = FeatureScopeMock()
        let watchdog = WatchdogTerminationMonitor(
            appStateManager: .mockRandom(),
            checker: .mockRandom(),
            storage: nil,
            feature: featureScope,
            reporter: WatchdogTerminationReporter.mockRandom()
        )
        watchdog.currentState = .started
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date(),
            dependencies: .mockWith(featureScope: featureScope, watchdogTermination: watchdog)
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        let representativeID = try XCTUnwrap(scope.activeView?.viewUUID.toRUMDataFormat)

        var resource = RUMStartResourceCommand.mockWith(resourceKey: "resource-A")
        resource.target = .scene(sceneA)
        _ = scope.process(command: resource, context: context, writer: writer)
        var stopResource = RUMStopResourceCommand.mockWith(resourceKey: "resource-A")
        stopResource.target = .scene(sceneA)
        _ = scope.process(command: stopResource, context: context, writer: writer)

        XCTAssertEqual(try storedWatchdogViewID(in: featureScope), representativeID)
    }

    func testGivenConcurrentScenes_whenRepresentativeViewStops_watchdogMovesToSurvivingRepresentative() throws {
        let featureScope = FeatureScopeMock()
        let watchdog = WatchdogTerminationMonitor(
            appStateManager: .mockRandom(),
            checker: .mockRandom(),
            storage: nil,
            feature: featureScope,
            reporter: WatchdogTerminationReporter.mockRandom()
        )
        watchdog.currentState = .started
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date(),
            dependencies: .mockWith(featureScope: featureScope, watchdogTermination: watchdog)
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewAIdentity = ViewIdentifier("view-A")
        let viewBIdentity = ViewIdentifier("view-B")

        _ = scope.process(
            command: startViewCommand(identity: viewAIdentity, name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: viewBIdentity, name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        let survivingViewID = try XCTUnwrap(
            scope.viewScopes.first(where: { $0.sceneIdentifier == sceneA })?.viewUUID.toRUMDataFormat
        )

        var stopB = RUMStopViewCommand.mockWith(identity: viewBIdentity)
        stopB.target = .scene(sceneB)
        _ = scope.process(command: stopB, context: context, writer: writer)

        XCTAssertEqual(scope.activeView?.sceneIdentifier, sceneA)
        XCTAssertEqual(try storedWatchdogViewID(in: featureScope), survivingViewID)
    }

    func testGivenSameViewIdentityInTwoScenes_whenOneStops_itKeepsOtherSceneActive() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let sharedIdentity = ViewIdentifier("shared-view")

        _ = scope.process(
            command: startViewCommand(identity: sharedIdentity, name: "Shared A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: sharedIdentity, name: "Shared B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )

        var stopA = RUMStopViewCommand.mockWith(identity: sharedIdentity)
        stopA.target = .scene(sceneA)
        _ = scope.process(command: stopA, context: context, writer: writer)

        XCTAssertEqual(scope.viewScopes.count, 1)
        XCTAssertEqual(scope.viewScopes.first?.sceneIdentifier, sceneB)
        XCTAssertEqual(scope.viewScopes.first?.viewName, "Shared B")
        XCTAssertTrue(try XCTUnwrap(scope.viewScopes.first).isActiveView)
    }

    func testGivenLegacyView_whenFirstSceneViewStarts_itPreservesSingleWindowReplacementSemantics() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(name: "Manual", path: "Manual"),
            context: context,
            writer: writer
        )
        XCTAssertEqual(scope.viewScopes.count, 1)
        XCTAssertNil(scope.viewScopes.first?.sceneIdentifier)

        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("automatic"),
                name: "Automatic",
                sceneIdentifier: sceneA
            ),
            context: context,
            writer: writer
        )

        XCTAssertEqual(scope.viewScopes.count, 1)
        XCTAssertEqual(scope.viewScopes.first?.sceneIdentifier, sceneA)
        XCTAssertEqual(scope.viewScopes.first?.viewName, "Automatic")
    }

    func testGivenConcurrentContinuousActions_whenRepresentativeActionStops_itDoesNotStopAnotherSceneAction() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )

        var startActionA = RUMStartUserActionCommand.mockWith(actionType: .scroll, name: "Scroll A")
        startActionA.target = .scene(sceneA)
        _ = scope.process(command: startActionA, context: context, writer: writer)

        var startActionB = RUMStartUserActionCommand.mockWith(actionType: .scroll, name: "Scroll B")
        startActionB.target = .scene(sceneB)
        _ = scope.process(command: startActionB, context: context, writer: writer)

        _ = scope.process(
            command: RUMStopUserActionCommand.mockWith(actionType: .swipe, name: "Scroll B"),
            context: context,
            writer: writer
        )

        let viewA = try XCTUnwrap(scope.viewScopes.first(where: { $0.sceneIdentifier == sceneA }))
        let viewB = try XCTUnwrap(scope.viewScopes.first(where: { $0.sceneIdentifier == sceneB }))
        XCTAssertNotNil(viewA.userActionScope)
        XCTAssertNil(viewB.userActionScope)

        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.view.name, "View B")
        XCTAssertEqual(actions.first?.action.target?.name, "Scroll B")
        XCTAssertEqual(actions.first?.action.type, .swipe)
    }

    func testGivenOverdueLegacyContinuousAction_whenStopped_itPreservesStopAttributes() throws {
        try assertOverdueLegacyActionPreservesStopAttributes(isContinuous: true)
    }

    func testGivenOverdueLegacyDiscreteAction_whenStopped_itPreservesStopAttributes() throws {
        try assertOverdueLegacyActionPreservesStopAttributes(isContinuous: false)
    }

    private func assertOverdueLegacyActionPreservesStopAttributes(isContinuous: Bool) throws {
        let startTime = Date(timeIntervalSinceReferenceDate: 0)
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: startTime)
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: startTime, name: "Legacy View", path: "Legacy View"),
            context: context,
            writer: writer
        )
        let view = try XCTUnwrap(scope.activeView)
        let attributes = ["started": "yes", "phase": "start"]
        let startAction: RUMCommand = isContinuous
            ? RUMStartUserActionCommand.mockWith(
                time: startTime, attributes: attributes, actionType: .tap, name: "Original action"
            )
            : RUMAddUserActionCommand.mockWith(
                time: startTime, attributes: attributes, actionType: .tap, name: "Original action"
            )
        _ = scope.process(command: startAction, context: context, writer: writer)
        let actionID = try XCTUnwrap(view.userActionScope?.actionUUID.toRUMDataFormat)
        let duration = isContinuous
            ? RUMUserActionScope.Constants.continuousActionMaxDuration
            : RUMUserActionScope.Constants.discreteActionTimeoutDuration
        XCTAssertTrue(writer.events(ofType: RUMActionEvent.self).isEmpty)

        _ = scope.process(
            command: RUMStopUserActionCommand.mockWith(
                time: startTime.addingTimeInterval(duration + 1),
                attributes: ["stopped": "yes", "phase": "stop"],
                actionType: .scroll,
                name: "Late replacement"
            ),
            context: context,
            writer: writer
        )

        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertEqual(action.action.id, actionID)
        XCTAssertEqual(action.view.id, view.viewUUID.toRUMDataFormat)
        XCTAssertEqual(action.action.loadingTime, duration.dd.toInt64Nanoseconds)
        XCTAssertEqual(action.action.target?.name, "Original action")
        XCTAssertEqual(action.action.type, .tap)
        XCTAssertEqual(action.context?.contextInfo["started"] as? String, "yes")
        XCTAssertEqual(action.context?.contextInfo["stopped"] as? String, "yes")
        XCTAssertEqual(action.context?.contextInfo["phase"] as? String, "stop")
        XCTAssertNil(view.userActionScope)
    }

    func testGivenOverdueConcurrentActions_whenExplicitStopTargetsA_itPreservesOnlyRecipientAttributes() throws {
        for useExactView in [false, true] {
            let writer = FileWriterMock()
            let startTime = Date()
            let scope: RUMSessionScope = .mockWith(parent: parent, startTime: startTime)
            let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
            let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
            for (scene, name) in [(sceneA, "A"), (sceneB, "B")] {
                _ = scope.process(
                    command: startViewCommand(
                        identity: ViewIdentifier(name), name: name, sceneIdentifier: scene, time: startTime
                    ),
                    context: context,
                    writer: writer
                )
                var startAction = RUMStartUserActionCommand.mockWith(
                    time: startTime, attributes: ["owner": name], actionType: .scroll, name: name
                )
                startAction.target = .scene(scene)
                _ = scope.process(command: startAction, context: context, writer: writer)
            }
            let viewA = try XCTUnwrap(scope.viewScopes.first { $0.sceneIdentifier == sceneA })
            let viewB = try XCTUnwrap(scope.viewScopes.first { $0.sceneIdentifier == sceneB })
            let actionAID = try XCTUnwrap(viewA.userActionScope?.actionUUID.toRUMDataFormat)
            let actionBID = try XCTUnwrap(viewB.userActionScope?.actionUUID.toRUMDataFormat)
            XCTAssertTrue(scope.activeView === viewB)
            XCTAssertTrue(writer.events(ofType: RUMActionEvent.self).isEmpty)
            var stopAction = RUMStopUserActionCommand.mockWith(
                time: startTime.addingTimeInterval(11),
                attributes: ["stopped": "A", "owner": "A-stop"],
                actionType: .swipe,
                name: "Late replacement"
            )
            stopAction.target = .scene(sceneB)
            stopAction.explicitTarget = useExactView ? .view(viewA.viewUUID) : .scene(sceneA)

            _ = scope.process(command: stopAction, context: context, writer: writer)

            let actions = writer.events(ofType: RUMActionEvent.self)
            XCTAssertEqual(actions.count, 2)
            let actionA = try XCTUnwrap(actions.first { $0.view.id == viewA.viewUUID.toRUMDataFormat })
            let actionB = try XCTUnwrap(actions.first { $0.view.id == viewB.viewUUID.toRUMDataFormat })
            XCTAssertEqual(actionA.action.id, actionAID)
            XCTAssertEqual(actionB.action.id, actionBID)
            XCTAssertEqual(actionA.action.target?.name, "A")
            XCTAssertEqual(actionB.action.target?.name, "B")
            XCTAssertEqual(actionA.action.type, .scroll)
            XCTAssertEqual(actionB.action.type, .scroll)
            XCTAssertEqual(actionA.action.loadingTime, 10_000_000_000)
            XCTAssertEqual(actionB.action.loadingTime, 10_000_000_000)
            XCTAssertEqual(actionA.context?.contextInfo["stopped"] as? String, "A")
            XCTAssertEqual(actionA.context?.contextInfo["owner"] as? String, "A-stop")
            XCTAssertNil(actionB.context?.contextInfo["stopped"])
            XCTAssertEqual(actionB.context?.contextInfo["owner"] as? String, "B")
            XCTAssertNil(viewA.userActionScope)
            XCTAssertNil(viewB.userActionScope)
        }
    }

    func testGivenOverdueAction_whenStopTargetsMissingScene_itExpiresWithoutForeignAttributes() throws {
        let startTime = Date()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: startTime)
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"), name: "A", sceneIdentifier: scene, time: startTime
            ),
            context: context,
            writer: writer
        )
        let view = try XCTUnwrap(scope.activeView)
        var startAction = RUMStartUserActionCommand.mockWith(
            time: startTime, attributes: ["owner": "A"], actionType: .scroll, name: "A"
        )
        startAction.target = .scene(scene)
        _ = scope.process(command: startAction, context: context, writer: writer)
        let actionID = try XCTUnwrap(view.userActionScope?.actionUUID.toRUMDataFormat)
        var stopAction = RUMStopUserActionCommand.mockWith(
            time: startTime.addingTimeInterval(11), attributes: ["stopped": "missing", "owner": "missing"]
        )
        stopAction.target = .scene(.init(rawValue: "missing-scene"))

        _ = scope.process(command: stopAction, context: context, writer: writer)

        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertEqual(action.action.id, actionID)
        XCTAssertEqual(action.view.id, view.viewUUID.toRUMDataFormat)
        XCTAssertEqual(action.action.loadingTime, 10_000_000_000)
        XCTAssertEqual(action.context?.contextInfo["owner"] as? String, "A")
        XCTAssertNil(action.context?.contextInfo["stopped"])
        XCTAssertNil(view.userActionScope)
    }

    func testGivenDiscreteActionInOneScene_whenOnlyAnotherSceneInteracts_itStillExpiresTheFirstAction() throws {
        let startTime = Date()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: startTime)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                time: startTime,
                attributes: ["origin": "A"],
                actionType: .tap,
                name: "Tap A",
                target: .scene(sceneA)
            ),
            context: context,
            writer: writer
        )

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                time: startTime.addingTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration),
                attributes: ["origin": "B"],
                actionType: .custom,
                name: "Action B",
                target: .scene(sceneB)
            ),
            context: context,
            writer: writer
        )

        let viewA = try XCTUnwrap(scope.viewScopes.first(where: { $0.sceneIdentifier == sceneA }))
        XCTAssertNil(viewA.userActionScope)

        let actionA = try XCTUnwrap(
            writer.events(ofType: RUMActionEvent.self).first(where: { $0.action.target?.name == "Tap A" })
        )
        XCTAssertEqual(actionA.view.name, "View A")
        XCTAssertEqual(actionA.context?.contextInfo["origin"] as? String, "A")
    }

    func testGivenConcurrentScenes_whenNavigatingInOneScene_itLeavesOtherSceneActive() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewA1 = ViewIdentifier("view-A-1")
        let viewA2 = ViewIdentifier("view-A-2")
        let viewB = ViewIdentifier("view-B")

        _ = scope.process(
            command: startViewCommand(identity: viewA1, name: "View A1", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: viewB, name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: viewA2, name: "View A2", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )

        XCTAssertEqual(scope.viewScopes.filter(\.isActiveView).count, 2)
        XCTAssertNil(scope.viewScopes.first(where: { $0.identity == viewA1 }))
        XCTAssertTrue(try XCTUnwrap(scope.viewScopes.first(where: { $0.identity == viewA2 })).isActiveView)
        XCTAssertTrue(try XCTUnwrap(scope.viewScopes.first(where: { $0.identity == viewB })).isActiveView)
        XCTAssertEqual(scope.activeView?.identity, viewA2)
    }

    func testGivenConcurrentScenes_whenUnscopedViewStarts_itReplacesRepresentativeSceneOnly() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .custom,
                name: "Select A",
                target: .scene(sceneA)
            ),
            context: context,
            writer: writer
        )

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                identity: ViewIdentifier("manual-view"),
                name: "Manual View",
                path: "Manual View"
            ),
            context: context,
            writer: writer
        )

        XCTAssertEqual(scope.viewScopes.filter(\.isActiveView).count, 2)
        XCTAssertNil(scope.viewScopes.first(where: { $0.identity == ViewIdentifier("view-A") }))
        XCTAssertEqual(
            scope.viewScopes.first(where: { $0.identity == ViewIdentifier("manual-view") })?.sceneIdentifier,
            sceneA
        )
        XCTAssertTrue(try XCTUnwrap(scope.viewScopes.first(where: { $0.identity == ViewIdentifier("view-B") })).isActiveView)
    }

    func testGivenConcurrentScenes_whenUnscopedStopMatchesEarlierSceneIdentity_itStopsThatScene() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewA = ViewIdentifier("view-A")

        _ = scope.process(
            command: startViewCommand(identity: viewA, name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )

        _ = scope.process(
            command: RUMStopViewCommand.mockWith(identity: viewA),
            context: context,
            writer: writer
        )

        XCTAssertNil(scope.viewScopes.first(where: { $0.identity == viewA }))
        XCTAssertEqual(scope.viewScopes.filter(\.isActiveView).count, 1)
        XCTAssertEqual(scope.activeView?.sceneIdentifier, sceneB)
    }

    func testGivenConcurrentScenes_whenActionTargetsEarlierScene_itUsesThatSceneViewOnce() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        let viewAID = try XCTUnwrap(scope.activeView?.viewUUID.toRUMDataFormat)
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )

        var action = RUMAddUserActionCommand.mockWith(actionType: .custom, name: "Action in A")
        action.target = .scene(sceneA)
        _ = scope.process(command: action, context: context, writer: writer)

        let actionEvents = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actionEvents.count, 1)
        XCTAssertEqual(actionEvents.first?.view.id, viewAID)
        XCTAssertEqual(actionEvents.first?.view.name, "View A")
        XCTAssertEqual(scope.activeView?.sceneIdentifier, sceneA)
    }

    func testGivenConcurrentScenes_whenActionTargetsExactEarlierView_itBecomesRepresentativeForLaterSourceLessWork() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        let viewAID = try XCTUnwrap(scope.activeView?.viewUUID)
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .tap,
                name: "Exact action in A",
                target: .view(viewAID)
            ),
            context: context,
            writer: writer
        )
        let resourceStartTime = Date().addingTimeInterval(1)
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(
                resourceKey: "later-resource",
                time: resourceStartTime
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(
                resourceKey: "later-resource",
                time: resourceStartTime.addingTimeInterval(1)
            ),
            context: context,
            writer: writer
        )

        let actionEvents = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actionEvents.count, 1)
        XCTAssertEqual(actionEvents.first?.view.id, viewAID.toRUMDataFormat)
        let resourceEvents = writer.events(ofType: RUMResourceEvent.self)
        XCTAssertEqual(resourceEvents.count, 1)
        XCTAssertEqual(resourceEvents.first?.view.id, viewAID.toRUMDataFormat)
        XCTAssertEqual(scope.activeView?.sceneIdentifier, sceneA)
    }

    func testGivenConcurrentScenes_whenUnscopedActionIsAdded_itDoesNotDuplicateIt() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        let representativeViewID = try XCTUnwrap(scope.activeView?.viewUUID.toRUMDataFormat)

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(actionType: .custom, name: "Legacy action"),
            context: context,
            writer: writer
        )

        let actionEvents = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actionEvents.count, 1)
        XCTAssertEqual(actionEvents.first?.view.id, representativeViewID)
    }

    func testGivenConcurrentScenesWithActionInEarlierScene_whenUnscopedActionIsAdded_itDoesNotDuplicateIt() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .tap,
                name: "Ongoing action in A",
                target: .scene(sceneA)
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        let representativeViewID = try XCTUnwrap(scope.activeView?.viewUUID.toRUMDataFormat)

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(actionType: .custom, name: "Legacy action"),
            context: context,
            writer: writer
        )

        let legacyActionEvents = writer.events(ofType: RUMActionEvent.self)
            .filter { $0.action.target?.name == "Legacy action" }
        XCTAssertEqual(legacyActionEvents.count, 1)
        XCTAssertEqual(legacyActionEvents.first?.view.id, representativeViewID)
    }

    func testGivenConcurrentScenes_whenResourceCompletesAfterAnotherSceneInteracts_itKeepsItsCapturedView() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        let viewAID = try XCTUnwrap(scope.activeView?.viewUUID)
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )

        let resourceKey = "resource-owned-by-A"
        var startResource = RUMStartResourceCommand.mockWith(resourceKey: resourceKey)
        startResource.target = .view(viewAID)
        _ = scope.process(command: startResource, context: context, writer: writer)

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .custom,
                name: "Action in B",
                target: .scene(sceneB)
            ),
            context: context,
            writer: writer
        )
        XCTAssertEqual(scope.activeView?.sceneIdentifier, sceneB)

        var stopResource = RUMStopResourceCommand.mockWith(resourceKey: resourceKey)
        stopResource.target = .view(viewAID)
        _ = scope.process(command: stopResource, context: context, writer: writer)

        let resourceEvents = writer.events(ofType: RUMResourceEvent.self)
        XCTAssertEqual(resourceEvents.count, 1)
        XCTAssertEqual(resourceEvents.first?.view.id, viewAID.toRUMDataFormat)
        XCTAssertEqual(resourceEvents.first?.view.name, "View A")
    }

    func testUnknownResourceCompletionDoesNotChangeCurrentActionCounts() throws {
        let time = Date()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: time)
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("A"), name: "A", sceneIdentifier: scene, time: time),
            context: context,
            writer: writer
        )
        var action = RUMStartUserActionCommand.mockWith(time: time, actionType: .tap, name: "Current")
        action.target = .scene(scene)
        _ = scope.process(command: action, context: context, writer: writer)
        _ = scope.process(
            command: RUMAddResourceMetricsCommand.mockWith(resourceKey: "unknown", time: time.addingTimeInterval(0.01)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: "unknown", time: time.addingTimeInterval(0.02)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "unknown", time: time.addingTimeInterval(0.03)),
            context: context,
            writer: writer
        )
        var stop = RUMStopUserActionCommand.mockWith(time: time.addingTimeInterval(0.04), actionType: .tap)
        stop.target = .scene(scene)
        _ = scope.process(command: stop, context: context, writer: writer)

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(event.action.resource?.count, 0)
        XCTAssertEqual(event.action.error?.count, 0)
        XCTAssertTrue(writer.events(ofType: RUMResourceEvent.self).isEmpty)
        XCTAssertTrue(writer.events(ofType: RUMErrorEvent.self).isEmpty)
    }

    func testUnownedResourceCommandStillExpiresUnrelatedActionAtItsDeadline() throws {
        let time = Date(timeIntervalSinceReferenceDate: 0)
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: time)
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("A"), name: "A", sceneIdentifier: scene, time: time),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: time, actionType: .tap, name: "Tap", target: .scene(scene)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddResourceMetricsCommand.mockWith(resourceKey: "unknown", time: time.addingTimeInterval(0.05)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "unknown", time: time.addingTimeInterval(0.2)),
            context: context,
            writer: writer
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(event.action.loadingTime, 100_000_000)
        XCTAssertEqual(event.action.error?.count, 0)
        XCTAssertEqual(event.action.resource?.count, 0)
        XCTAssertNil(scope.activeView?.userActionScope)
    }

    func testGivenAOwnedResourceAndBAction_whenSourceLessResourceSucceeds_itDoesNotIncrementBAction() throws {
        let startTime = Date()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: startTime)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"),
                name: "View A",
                sceneIdentifier: sceneA,
                time: startTime
            ),
            context: context,
            writer: writer
        )
        let viewAID = try XCTUnwrap(scope.activeView?.viewUUID)
        var startResource = RUMStartResourceCommand.mockWith(
            resourceKey: "resource-owned-by-A",
            time: startTime.addingTimeInterval(0.01)
        )
        startResource.target = .view(viewAID)
        _ = scope.process(command: startResource, context: context, writer: writer)

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-B"),
                name: "View B",
                sceneIdentifier: sceneB,
                time: startTime.addingTimeInterval(0.02)
            ),
            context: context,
            writer: writer
        )
        var startAction = RUMStartUserActionCommand.mockWith(
            time: startTime.addingTimeInterval(0.03),
            actionType: .tap,
            name: "Tap B"
        )
        startAction.target = .scene(sceneB)
        _ = scope.process(command: startAction, context: context, writer: writer)

        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(
                resourceKey: "resource-owned-by-A",
                time: startTime.addingTimeInterval(0.04)
            ),
            context: context,
            writer: writer
        )
        var stopAction = RUMStopUserActionCommand.mockWith(
            time: startTime.addingTimeInterval(0.05),
            actionType: .tap,
            name: "Tap B"
        )
        stopAction.target = .scene(sceneB)
        _ = scope.process(command: stopAction, context: context, writer: writer)

        let resource = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).last)
        XCTAssertEqual(resource.view.id, viewAID.toRUMDataFormat)
        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(action.view.name, "View B")
        XCTAssertEqual(action.action.resource?.count, 0)
    }

    func testGivenAOwnedResourceAndBAction_whenSourceLessResourceFails_itDoesNotIncrementBAction() throws {
        let startTime = Date()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: startTime)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"),
                name: "View A",
                sceneIdentifier: sceneA,
                time: startTime
            ),
            context: context,
            writer: writer
        )
        let viewAID = try XCTUnwrap(scope.activeView?.viewUUID)
        var startResource = RUMStartResourceCommand.mockWith(
            resourceKey: "resource-owned-by-A",
            time: startTime.addingTimeInterval(0.01)
        )
        startResource.target = .view(viewAID)
        _ = scope.process(command: startResource, context: context, writer: writer)

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-B"),
                name: "View B",
                sceneIdentifier: sceneB,
                time: startTime.addingTimeInterval(0.02)
            ),
            context: context,
            writer: writer
        )
        var startAction = RUMStartUserActionCommand.mockWith(
            time: startTime.addingTimeInterval(0.03),
            actionType: .tap,
            name: "Tap B"
        )
        startAction.target = .scene(sceneB)
        _ = scope.process(command: startAction, context: context, writer: writer)

        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(
                resourceKey: "resource-owned-by-A",
                time: startTime.addingTimeInterval(0.04),
                message: "resource failed"
            ),
            context: context,
            writer: writer
        )
        var stopAction = RUMStopUserActionCommand.mockWith(
            time: startTime.addingTimeInterval(0.05),
            actionType: .tap,
            name: "Tap B"
        )
        stopAction.target = .scene(sceneB)
        _ = scope.process(command: stopAction, context: context, writer: writer)

        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(error.view.id, viewAID.toRUMDataFormat)
        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(action.view.name, "View B")
        XCTAssertEqual(action.action.error?.count, 0)
        XCTAssertFalse(action.action.frustration?.type.contains(.errorTap) == true)
    }

    func testGivenResourceOwnedByInactiveView_whenItCompletes_itDoesNotAlsoReachCurrentViewsAction() throws {
        let startTime = Date()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: startTime)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A1"),
                name: "View A1",
                sceneIdentifier: sceneA,
                time: startTime
            ),
            context: context,
            writer: writer
        )
        let viewA1ID = try XCTUnwrap(scope.activeView?.viewUUID)

        let resourceKey = "resource-owned-by-A1"
        var startResource = RUMStartResourceCommand.mockWith(
            resourceKey: resourceKey,
            time: startTime.addingTimeInterval(0.01)
        )
        startResource.target = .view(viewA1ID)
        _ = scope.process(command: startResource, context: context, writer: writer)

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A2"),
                name: "View A2",
                sceneIdentifier: sceneA,
                time: startTime.addingTimeInterval(0.02)
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                time: startTime.addingTimeInterval(0.03),
                actionType: .tap,
                name: "Action in A2",
                target: .scene(sceneA)
            ),
            context: context,
            writer: writer
        )

        var stopResource = RUMStopResourceCommand.mockWith(
            resourceKey: resourceKey,
            time: startTime.addingTimeInterval(0.04)
        )
        stopResource.target = .view(viewA1ID)
        _ = scope.process(command: stopResource, context: context, writer: writer)

        var expireAction = RUMStopUserActionCommand(
            time: startTime.addingTimeInterval(0.2),
            globalAttributes: [:],
            attributes: [:],
            actionType: .tap,
            name: nil
        )
        expireAction.target = .scene(sceneA)
        _ = scope.process(command: expireAction, context: context, writer: writer)

        let resource = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).last)
        XCTAssertEqual(resource.view.id, viewA1ID.toRUMDataFormat)
        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(action.view.name, "View A2")
        XCTAssertEqual(action.action.resource?.count, 0)
    }

    func testGivenCachedLegacyViewAndActiveSceneView_whenExactErrorArrives_itKeepsLegacyFallback() throws {
        let dateProvider = RelativeDateProvider()
        let viewCache = ViewCache(dateProvider: dateProvider)
        let legacyViewID = RUMUUID(rawValue: UUID())
        viewCache.insert(
            id: legacyViewID.toRUMDataFormat,
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        )
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: dateProvider.now,
            dependencies: .mockWith(viewCache: viewCache)
        )
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"),
                name: "View A",
                sceneIdentifier: RUMSceneIdentifier(rawValue: "scene-A"),
                time: dateProvider.now
            ),
            context: context,
            writer: writer
        )

        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(message: "legacy delayed error")
        error.target = .view(legacyViewID)
        _ = scope.process(command: error, context: context, writer: writer)

        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(event.view.name, "View A")
    }

    func testGivenInactiveExactLegacyViewAndActiveSceneView_whenErrorArrives_itKeepsLegacyFallback() throws {
        let startTime = Date()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: startTime)
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime,
                identity: ViewIdentifier("legacy-view"),
                name: "Legacy View",
                path: "Legacy View"
            ),
            context: context,
            writer: writer
        )
        let legacyViewID = try XCTUnwrap(scope.activeView?.viewUUID)
        var keepLegacyAlive = RUMStartResourceCommand.mockWith(resourceKey: "legacy-resource")
        keepLegacyAlive.target = .view(legacyViewID)
        _ = scope.process(command: keepLegacyAlive, context: context, writer: writer)

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"),
                name: "View A",
                sceneIdentifier: RUMSceneIdentifier(rawValue: "scene-A"),
                time: startTime.addingTimeInterval(0.01)
            ),
            context: context,
            writer: writer
        )
        XCTAssertTrue(scope.viewScopes.contains { $0.viewUUID == legacyViewID && !$0.isActiveView })

        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(message: "exact legacy delayed error")
        error.target = .view(legacyViewID)
        _ = scope.process(command: error, context: context, writer: writer)

        let event = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(event.view.name, "View A")
    }

    func testGivenCapturedViewNoLongerExists_whenResourceRuns_itFallsBackWithoutLosingCompletion() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let initialView = ViewIdentifier("initial-view")
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(identity: initialView, name: "Initial", path: "Initial"),
            context: context,
            writer: writer
        )

        let missingViewID = RUMUUID(rawValue: UUID())
        let resourceKey = "resource-with-expired-owner"
        var startResource = RUMStartResourceCommand.mockWith(resourceKey: resourceKey)
        startResource.target = .view(missingViewID)
        _ = scope.process(command: startResource, context: context, writer: writer)

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                identity: ViewIdentifier("next-view"),
                name: "Next",
                path: "Next"
            ),
            context: context,
            writer: writer
        )

        var stopResource = RUMStopResourceCommand.mockWith(resourceKey: resourceKey)
        stopResource.target = .view(missingViewID)
        _ = scope.process(command: stopResource, context: context, writer: writer)

        let resourceEvents = writer.events(ofType: RUMResourceEvent.self)
        XCTAssertEqual(resourceEvents.count, 1)
        XCTAssertEqual(resourceEvents.first?.view.name, "Initial")
    }

    func testGivenCapturedViewNoLongerExists_whenErrorArrives_itFallsBackToRepresentativeView() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(name: "Representative", path: "Representative"),
            context: context,
            writer: writer
        )

        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(message: "delayed error")
        error.target = .view(RUMUUID(rawValue: UUID()))
        _ = scope.process(command: error, context: context, writer: writer)

        let errorEvents = writer.events(ofType: RUMErrorEvent.self)
        XCTAssertEqual(errorEvents.count, 1)
        XCTAssertEqual(errorEvents.first?.view.name, "Representative")
    }

    func testGivenUnknownCapturedViewAndConcurrentScenes_whenErrorArrives_itDoesNotGuessAnotherScene() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"),
                name: "View A",
                sceneIdentifier: .init(rawValue: "scene-A")
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-B"),
                name: "View B",
                sceneIdentifier: .init(rawValue: "scene-B")
            ),
            context: context,
            writer: writer
        )

        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(message: "delayed error")
        error.target = .view(RUMUUID(rawValue: UUID()))
        _ = scope.process(command: error, context: context, writer: writer)

        XCTAssertTrue(writer.events(ofType: RUMErrorEvent.self).isEmpty)
    }

    func testGivenCapturedSceneViewNoLongerExists_whenErrorArrives_itFallsBackWithinTheSameScene() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A-1"), name: "View A1", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        let capturedViewAID = try XCTUnwrap(scope.activeView?.viewUUID)
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A-2"), name: "View A2", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .custom,
                name: "Make B representative",
                target: .scene(sceneB)
            ),
            context: context,
            writer: writer
        )

        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(message: "delayed error from A")
        error.target = .view(capturedViewAID)
        _ = scope.process(command: error, context: context, writer: writer)

        let errorEvent = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(errorEvent.view.name, "View A2")
    }

    func testGivenCapturedSceneViewAndItsSceneNoLongerExist_whenErrorArrives_itDoesNotUseAnotherScene() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewA = ViewIdentifier("view-A")

        _ = scope.process(
            command: startViewCommand(identity: viewA, name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        let capturedViewAID = try XCTUnwrap(scope.activeView?.viewUUID)
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        var stopA = RUMStopViewCommand.mockWith(identity: viewA)
        stopA.target = .scene(sceneA)
        _ = scope.process(command: stopA, context: context, writer: writer)

        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(message: "delayed error from closed A")
        error.target = .view(capturedViewAID)
        _ = scope.process(command: error, context: context, writer: writer)

        XCTAssertTrue(writer.events(ofType: RUMErrorEvent.self).isEmpty)
    }

    func testGivenCapturedViewOwnershipExpiredAndOneOtherSceneRemains_whenErrorArrives_itDoesNotGuessThatScene() throws {
        let dateProvider = RelativeDateProvider()
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: 1)
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: dateProvider.now,
            dependencies: .mockWith(viewCache: viewCache)
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewAIdentity = ViewIdentifier("view-A")
        _ = scope.process(
            command: startViewCommand(
                identity: viewAIdentity,
                name: "View A",
                sceneIdentifier: sceneA,
                time: dateProvider.now
            ),
            context: context,
            writer: writer
        )
        let capturedViewAID = try XCTUnwrap(scope.activeView?.viewUUID)
        var stopA = RUMStopViewCommand.mockWith(time: dateProvider.now, identity: viewAIdentity)
        stopA.target = .scene(sceneA)
        _ = scope.process(command: stopA, context: context, writer: writer)

        dateProvider.advance(bySeconds: 2)
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-B"),
                name: "View B",
                sceneIdentifier: sceneB,
                time: dateProvider.now
            ),
            context: context,
            writer: writer
        )
        XCTAssertNil(viewCache.sceneIdentifier(forViewID: capturedViewAID.toRUMDataFormat))

        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(message: "delayed error from A")
        error.target = .view(capturedViewAID)
        _ = scope.process(command: error, context: context, writer: writer)

        XCTAssertTrue(writer.events(ofType: RUMErrorEvent.self).isEmpty)
    }

    func testGivenOperationStartedInOneScene_whenItEndsThereAfterNavigation_itOverridesAnotherProcessRepresentative() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A-1"),
                name: "View A1",
                sceneIdentifier: sceneA
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-B"),
                name: "View B",
                sceneIdentifier: sceneB
            ),
            context: context,
            writer: writer
        )
        let operationKey = "operation-A"
        var operationStart = RUMOperationStepVitalCommand(
            vitalId: UUID().uuidString,
            name: "load_note",
            operationKey: operationKey,
            stepType: .start,
            failureReason: nil,
            time: Date(),
            attributes: [:]
        )
        operationStart.target = .scene(sceneA)
        _ = scope.process(
            command: operationStart,
            context: context,
            writer: writer
        )

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A-2"),
                name: "View A2",
                sceneIdentifier: sceneA
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .custom,
                name: "Interaction in B",
                target: .scene(sceneB)
            ),
            context: context,
            writer: writer
        )
        XCTAssertEqual(scope.activeView?.sceneIdentifier, sceneB)

        var operationEnd = RUMOperationStepVitalCommand(
            vitalId: UUID().uuidString,
            name: "load_note",
            operationKey: operationKey,
            stepType: .end,
            failureReason: nil,
            time: Date(),
            attributes: [:]
        )
        operationEnd.target = .scene(sceneA)
        _ = scope.process(
            command: operationEnd,
            context: context,
            writer: writer
        )

        let operationEvents = writer.events(ofType: RUMVitalOperationStepEvent.self)
        XCTAssertEqual(operationEvents.count, 2)
        XCTAssertEqual(operationEvents[0].view.url, "View A1")
        XCTAssertEqual(operationEvents[1].view.url, "View A2")
    }

    func testGivenOperationStartedInSceneA_whenItEndsInSceneB_itUsesEachScenesCurrentView() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"),
                name: "Message List",
                sceneIdentifier: sceneA
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-B"),
                name: "Full Thread",
                sceneIdentifier: sceneB
            ),
            context: context,
            writer: writer
        )

        var operationStart = RUMOperationStepVitalCommand(
            vitalId: UUID().uuidString,
            name: "thread_open",
            operationKey: "key-123",
            stepType: .start,
            failureReason: nil,
            time: Date(),
            attributes: [:]
        )
        operationStart.target = .scene(sceneA)
        _ = scope.process(command: operationStart, context: context, writer: writer)

        var operationEnd = RUMOperationStepVitalCommand(
            vitalId: UUID().uuidString,
            name: "thread_open",
            operationKey: "key-123",
            stepType: .end,
            failureReason: nil,
            time: Date(),
            attributes: [:]
        )
        operationEnd.target = .scene(sceneB)
        _ = scope.process(command: operationEnd, context: context, writer: writer)

        let operationEvents = writer.events(ofType: RUMVitalOperationStepEvent.self)
        XCTAssertEqual(operationEvents.count, 2)
        XCTAssertEqual(operationEvents[0].view.url, "Message List")
        XCTAssertEqual(operationEvents[1].view.url, "Full Thread")
    }

    func testGivenOperationTargetSceneHasNoView_whenNoSnapshot_itUsesProcessRepresentative() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"),
                name: "View A",
                sceneIdentifier: sceneA
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-B"),
                name: "View B",
                sceneIdentifier: sceneB
            ),
            context: context,
            writer: writer
        )

        var operationStart = RUMOperationStepVitalCommand(
            vitalId: UUID().uuidString,
            name: "operation",
            operationKey: "key",
            stepType: .start,
            failureReason: nil,
            time: Date(),
            attributes: [:]
        )
        operationStart.target = .scene(RUMSceneIdentifier(rawValue: "missing-scene"))
        _ = scope.process(command: operationStart, context: context, writer: writer)

        let event = try XCTUnwrap(writer.events(ofType: RUMVitalOperationStepEvent.self).last)
        XCTAssertEqual(event.view.url, "View B")
    }

    func testGivenConcurrentScenes_whenSessionStops_itStopsEverySceneView() {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A"), name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )

        _ = scope.process(command: RUMStopSessionCommand.mockWith(), context: context, writer: writer)

        XCTAssertFalse(scope.isActive)
        XCTAssertTrue(scope.viewScopes.isEmpty)
    }

    func testGivenConcurrentScenes_itKeepsIndependentINVHistories() {
        var metrics: [INVMetricMock] = []
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date(),
            dependencies: .mockWith(
                interactionToNextViewMetricFactory: {
                    let metric = INVMetricMock()
                    metrics.append(metric)
                    return metric
                }
            )
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A-1"), name: "View A1", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .custom,
                name: "Action in A",
                target: .scene(sceneA)
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-A-2"), name: "View A2", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )

        XCTAssertEqual(metrics.count, 3, "legacy fallback plus one tracker for each scene")
        XCTAssertEqual(metrics[0].trackedViewStarts.count, 0)
        XCTAssertEqual(metrics[1].trackedViewStarts.map(\.viewName), ["View A1", "View A2"])
        XCTAssertEqual(metrics[1].trackedActions.map(\.actionName), ["Action in A"])
        XCTAssertEqual(metrics[2].trackedViewStarts.map(\.viewName), ["View B"])
        XCTAssertTrue(metrics[2].trackedActions.isEmpty)
    }

    func testWhenViewStarts_itUpdatesTheViewCache() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        let ttl: TimeInterval = .mockRandom(min: 2, max: 10)
        let viewCache = ViewCache(dateProvider: SystemDateProvider(), ttl: ttl)

        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: dateProvider.now,
            dependencies: .mockWith(viewCache: viewCache)
        )

        // When - starting a view
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: dateProvider.now,
                attributes: ["foo": "bar 2"],
                identity: .mockRandomString()
            ),
            context: context,
            writer: writer
        )

        dateProvider.advance(bySeconds: 1)

        // Then - the view is added to the cache
        let firstViewID = try XCTUnwrap(scope.viewScopes.first?.context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(viewCache.lastView(before: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds), firstViewID)

        // When - updating the view
        dateProvider.advance(bySeconds: ttl)

        _ = scope.process(
            command: RUMStopViewCommand.mockWith(
                time: dateProvider.now
            ),
            context: context,
            writer: writer
        )

        // Then - it updates the timestamp in cache
        XCTAssertEqual(viewCache.lastView(before: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds), firstViewID)
    }

    // MARK: - Background Events Tracking

    func testGivenAppInBackgroundAndNoViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanStartBackgroundView_itCreatesBackgroundScope() {
        // Given
        let sessionStartTime = Date()

        var context = self.context
        context.applicationStateHistory = .mockAppInBackground(since: sessionStartTime) // app in background

        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                trackBackgroundEvents: true // BET enabled
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: true)
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, commandTime, "Background view should be started at command time")
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMOffViewEventsHandlingRule.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMOffViewEventsHandlingRule.Constants.backgroundViewURL)
    }

    func testGivenAppInBackgroundAndNoActiveViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanStartBackgroundView_itCreatesBackgroundScope() {
        // Given
        let sessionStartTime = Date()

        var context = self.context
        context.applicationStateHistory = .mockAppInBackground(since: sessionStartTime) // app in background

        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                trackBackgroundEvents: true // BET enabled
            )
        )

        var commandTime = sessionStartTime.addingTimeInterval(1)
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: commandTime, identity: ViewIdentifier("view")), context: context, writer: writer)
        _ = scope.process(command: RUMStartResourceCommand.mockAny(), context: context, writer: writer)
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: commandTime.addingTimeInterval(0.5), identity: ViewIdentifier("view")), context: context, writer: writer)

        XCTAssertEqual(scope.viewScopes.count, 1, "There is one view scope...")
        XCTAssertFalse(scope.viewScopes[0].isActiveView, "... but the view is not active")

        // When
        commandTime = commandTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: true)
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 2, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[1].viewStartTime, commandTime, "Background view should be started at command time")
        XCTAssertEqual(scope.viewScopes[1].viewName, RUMOffViewEventsHandlingRule.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[1].viewPath, RUMOffViewEventsHandlingRule.Constants.backgroundViewURL)
    }

    func testGivenSceneAViewAndSceneBBackgroundView_whenSceneAActs_itDoesNotDuplicateIntoBackground() throws {
        let sessionStartTime = Date()
        var backgroundContext = context
        backgroundContext.applicationStateHistory = .mockAppInBackground(since: sessionStartTime)
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(trackBackgroundEvents: true)
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"),
                name: "View A",
                sceneIdentifier: sceneA,
                time: sessionStartTime
            ),
            context: backgroundContext,
            writer: writer
        )

        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(message: "scene B background error")
        error.target = .scene(sceneB)
        _ = scope.process(command: error, context: backgroundContext, writer: writer)

        let backgroundView = try XCTUnwrap(scope.viewScopes.first(where: {
            $0.sceneIdentifier == sceneB && $0.viewPath == RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
        }))
        XCTAssertTrue(backgroundView.isActiveView)

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .custom,
                name: "Scene A action",
                target: .scene(sceneA)
            ),
            context: backgroundContext,
            writer: writer
        )

        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(action.view.name, "View A")
        XCTAssertEqual(writer.events(ofType: RUMActionEvent.self).count, 1)
    }

    func testGivenConcurrentScenesAndBET_whenUnknownExactViewErrorArrives_itDoesNotCreateLegacyBackgroundView() {
        let sessionStartTime = Date()
        var backgroundContext = context
        backgroundContext.applicationStateHistory = .mockAppInBackground(since: sessionStartTime)
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(trackBackgroundEvents: true)
        )
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-A"),
                name: "View A",
                sceneIdentifier: RUMSceneIdentifier(rawValue: "scene-A"),
                time: sessionStartTime
            ),
            context: backgroundContext,
            writer: writer
        )
        _ = scope.process(
            command: startViewCommand(
                identity: ViewIdentifier("view-B"),
                name: "View B",
                sceneIdentifier: RUMSceneIdentifier(rawValue: "scene-B"),
                time: sessionStartTime
            ),
            context: backgroundContext,
            writer: writer
        )
        let initialScopeCount = scope.viewScopes.count

        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(message: "unknown-view error")
        error.target = .view(RUMUUID(rawValue: UUID()))
        _ = scope.process(command: error, context: backgroundContext, writer: writer)

        XCTAssertEqual(scope.viewScopes.count, initialScopeCount)
        XCTAssertFalse(scope.viewScopes.contains {
            $0.sceneIdentifier == nil
                && $0.viewPath == RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
        })
        XCTAssertTrue(writer.events(ofType: RUMErrorEvent.self).isEmpty)
    }

    func testGivenAppInBackgroundAndNoViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanNotStartBackgroundView_itDoesNotCreateBackgroundScope() {
        // Given
        let sessionStartTime = Date()

        var context = self.context
        context.applicationStateHistory = .mockAppInBackground(since: sessionStartTime) // app in background

        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                trackBackgroundEvents: true // BET enabled
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: false)
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    func testGivenAppInAnyStateAndNoViewScopeAndBackgroundEventsTrackingDisabled_whenReceivingAnyCommand_itDoesNotCreateBackgroundScope() {
        // Given
        let sessionStartTime = Date()

        var context = self.context
        context.applicationStateHistory = .mockRandom(since: sessionStartTime) // no matter of app state (if foreground or background)

        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                trackBackgroundEvents: false // BET disabled
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: .mockRandom())
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    // MARK: - Application Launch Events Tracking

    func testGivenAppInForegroundAndNotInitialSessionWithNoViewTrackedBefore_itDoesNotCreateAppLaunchScope() {
        // Given
        let sessionStartTime = Date()

        var context = self.context
        context.applicationStateHistory = .mockAppInForeground(since: sessionStartTime) // app in foreground

        let scope: RUMSessionScope = .mockWith(
            isInitialSession: false, // not initial session
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                trackBackgroundEvents: .mockRandom() // no matter of BET state
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: .mockRandom())
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    // MARK: - Sampling

    func testWhenSessionIsRejectedBySampler_itDoesNotCreateViewScopes() {
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date(),
            dependencies: .mockWith(samplingRate: 0)
        )

        XCTAssertEqual(scope.viewScopes.count, 0)
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer),
            "Rejected session should be kept until it expires or reaches the timeout."
        )
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    // MARK: - Updating Fatal Error Context

    func testWhenSessionScopeIsCreated_itUpdatesFatalErrorContextWithSessionState() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()
        let randomIsInitialSession: Bool = .mockRandom()
        let randomIsReplayBeingRecorded: Bool = .mockRandom()
        let randomSampleRate: SampleRate = .mockRandom(min: 0, max: 100)

        // When
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: randomIsInitialSession,
            parent: parent,
            context: .mockWith(
                additionalContext: [
                    SessionReplayCoreContext.HasReplay(value: randomIsReplayBeingRecorded)
                ]
            ),
            dependencies: .mockWith(
                featureScope: featureScope,
                samplingRate: randomSampleRate,
                fatalErrorContext: fatalErrorContext
            )
        )

        // Then
        let expectedSessionState = RUMSessionState(
            sessionUUID: scope.sessionUUID.rawValue,
            isSampled: DeterministicSampler(
                uuid: scope.sessionUUID.rawValue,
                samplingRate: randomSampleRate
            ).sample(),
            isInitialSession: randomIsInitialSession,
            hasTrackedAnyView: false,
            didStartWithReplay: randomIsReplayBeingRecorded
        )
        let actualSessionState = try XCTUnwrap(fatalErrorContext.sessionState)
        XCTAssertEqual(actualSessionState, expectedSessionState)
    }

    func testWhenSessionScopeStartsAnyView_itUpdatesFatalErrorContextWithSessionState() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()
        let randomIsInitialSession: Bool = .mockRandom()
        let randomIsReplayBeingRecorded: Bool = .mockRandom()

        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: randomIsInitialSession,
            parent: parent,
            startTime: sessionStartTime,
            context: .mockWith(
                additionalContext: [
                    SessionReplayCoreContext.HasReplay(value: randomIsReplayBeingRecorded)
                ]
            ),
            dependencies: .mockWith(
                featureScope: featureScope,
                fatalErrorContext: fatalErrorContext
            )
        )

        // When
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: sessionStartTime), context: context, writer: writer)

        XCTAssertFalse(scope.viewScopes.isEmpty, "Session started some view")

        // Then
        let expectedSessionState = RUMSessionState(
            sessionUUID: scope.sessionUUID.rawValue,
            isSampled: true,
            isInitialSession: randomIsInitialSession,
            hasTrackedAnyView: true,
            didStartWithReplay: randomIsReplayBeingRecorded
        )
        let actualSessionState = try XCTUnwrap(fatalErrorContext.sessionState)
        XCTAssertEqual(actualSessionState, expectedSessionState)
    }

    func testWhenSessionScopeHasNoActiveView_itUpdatesFatalErrorContextWithView() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()

        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                featureScope: featureScope,
                fatalErrorContext: fatalErrorContext
            )
        )

        // When
        let command = RUMStartViewCommand.mockWith(time: sessionStartTime, identity: .mockViewIdentifier(), name: "ActiveView")
        _ = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertEqual(fatalErrorContext.view?.view.name, "ActiveView")

        // When
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: sessionStartTime.addingTimeInterval(1), identity: .mockViewIdentifier()), context: context, writer: writer)

        // Then
        XCTAssertNil(fatalErrorContext.view)
    }

    func testGivenConcurrentScenes_fatalContextFollowsRepresentativeAndIgnoresOtherViewUpdates() throws {
        let fatalErrorContext = FatalErrorContextNotifierMock()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date(),
            dependencies: .mockWith(fatalErrorContext: fatalErrorContext)
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewA = ViewIdentifier("view-A")
        let viewB = ViewIdentifier("view-B")

        _ = scope.process(
            command: startViewCommand(identity: viewA, name: "View A", sceneIdentifier: sceneA),
            context: context,
            writer: writer
        )
        let viewAID = try XCTUnwrap(scope.activeView?.viewUUID)
        _ = scope.process(
            command: startViewCommand(identity: viewB, name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        XCTAssertEqual(fatalErrorContext.view?.view.name, "View B")

        var resource = RUMStartResourceCommand.mockWith(resourceKey: "resource-A")
        resource.target = .view(viewAID)
        _ = scope.process(command: resource, context: context, writer: writer)

        XCTAssertEqual(fatalErrorContext.view?.view.name, "View B")

        var stopB = RUMStopViewCommand.mockWith(identity: viewB)
        stopB.target = .scene(sceneB)
        _ = scope.process(command: stopB, context: context, writer: writer)

        XCTAssertEqual(fatalErrorContext.view?.view.name, "View A")
    }

    func testGivenLastRepresentativeSceneStops_itClearsCrashAndWatchdogContext() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()
        let watchdog = WatchdogTerminationMonitor(
            appStateManager: .mockRandom(),
            checker: .mockRandom(),
            storage: nil,
            feature: featureScope,
            reporter: WatchdogTerminationReporter.mockRandom()
        )
        watchdog.currentState = .started
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date(),
            dependencies: .mockWith(
                featureScope: featureScope,
                fatalErrorContext: fatalErrorContext,
                watchdogTermination: watchdog
            )
        )
        let viewA = ViewIdentifier("view-A")
        _ = scope.process(
            command: startViewCommand(
                identity: viewA,
                name: "View A",
                sceneIdentifier: RUMSceneIdentifier(rawValue: "scene-A")
            ),
            context: context,
            writer: writer
        )
        XCTAssertEqual(fatalErrorContext.view?.view.name, "View A")
        XCTAssertNotNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.watchdogRUMViewEvent.rawValue))

        var stopA = RUMStopViewCommand.mockWith(identity: viewA)
        stopA.target = .scene(RUMSceneIdentifier(rawValue: "scene-A"))
        _ = scope.process(command: stopA, context: context, writer: writer)

        XCTAssertNil(fatalErrorContext.view)
        XCTAssertNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.watchdogRUMViewEvent.rawValue))
    }

    func testWhenSessionEnds_itUpdatesFatalErrorContextWithView() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()

        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date(),
            dependencies: .mockWith(
                featureScope: featureScope,
                fatalErrorContext: fatalErrorContext
            )
        )

        let command = RUMStartViewCommand.mockWith(time: Date(), identity: .mockViewIdentifier(), name: "ActiveView")

        // When
        _ = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertEqual(fatalErrorContext.view?.view.name, "ActiveView")

        // When
        _ = scope.process(command: RUMStopSessionCommand.mockWith(time: Date()), context: context, writer: writer)

        // Then
        XCTAssertNil(fatalErrorContext.view)
    }

    // MARK: - Stopping Sessions

    func testGivenActiveSession_whenStopSessionEvent_itSetsSessionActiveFalse() {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )

        // When
        let command = RUMStopSessionCommand.mockWith(time: Date())

        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertFalse(scope.isActive)
        XCTAssertFalse(result)
    }

    func testGivenStoppedSession_itUpdatesContext() {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        _ = scope.process(command: RUMStopSessionCommand.mockWith(time: Date()), context: context, writer: writer)

        // When
        let context = scope.context

        XCTAssertFalse(context.isSessionActive)
    }

    func testGivenActiveSessionWithActiveView_whenStopSessionEvent_itStopsTheActiveView() throws {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: Date()), context: context, writer: writer)
        let view = try XCTUnwrap(scope.viewScopes.first)

        // When
        let command = RUMStopSessionCommand.mockWith(time: Date())

        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertFalse(view.isActiveView)
        XCTAssertFalse(result)
    }

    func testWhenSessionScopeHasViewsWithPendingResources_whenStopSession_itKeepsTheScope() throws {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockWith(time: Date()), context: context, writer: writer))
        XCTAssertTrue(scope.process(command: RUMStartResourceCommand.mockWith(time: Date()), context: context, writer: writer))
        let view = try XCTUnwrap(scope.viewScopes.first)

        // When
        let command: RUMStopSessionCommand = .mockWith(time: Date())
        let keep = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertFalse(scope.isActive)
        XCTAssertFalse(view.isActiveView)
        XCTAssertTrue(keep, "The scope should be kept because it has pending events")
    }

    func testWhenSessionScopeHasViewsWithPendingResources_itClosesTheScopeWhenResourcesFinish() throws {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: Date()), context: context, writer: writer)
        let startResourceCommand = RUMStartResourceCommand.mockWith(time: Date())
        XCTAssertTrue(scope.process(command: startResourceCommand, context: context, writer: writer))
        XCTAssertTrue(scope.process(command: RUMStopSessionCommand.mockWith(time: Date()), context: context, writer: writer))

        // When
        let command = RUMStopResourceCommand.mockWith(resourceKey: startResourceCommand.resourceKey, time: Date())
        let keep = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertFalse(scope.isActive)
        XCTAssertFalse(keep, "The scope should be closed")
    }

    func testWhenScopeEnded_itDoesNotStartNewViews() throws {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        _ = scope.process(command: RUMStopSessionCommand.mockWith(time: Date()), context: context, writer: writer)

        // When
        let command = RUMStartViewCommand.mockWith(time: Date())
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty)
        XCTAssertFalse(result)
    }

    func testWhenScopeEnded_itDoesNotCreateAnApplicationLaunchView() {
        // Note - This should happen because the application context should prevent against
        // it, but just in case
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        _ = scope.process(command: RUMStopSessionCommand.mockWith(time: Date()), context: context, writer: writer)

        // When
        let command = RUMApplicationStartCommand(time: Date(), globalAttributes: [:], attributes: [:])
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty)
        XCTAssertFalse(result)
    }

    // MARK: - Usage

    func testGivenSessionWithNoActiveScope_whenReceivingRUMCommand_itLogsWarning() throws {
        func recordWarningOnReceiving(command: RUMCommand) -> String? {
            // Given
            let scope: RUMSessionScope = .mockWith(
                parent: parent,
                startTime: Date()
            )
            XCTAssertEqual(scope.viewScopes.count, 0)

            let dd = DD.mockWith(logger: CoreLoggerMock())
            defer { dd.reset() }

            // When
            _ = scope.process(command: command, context: context, writer: writer)

            // Then
            XCTAssertEqual(scope.viewScopes.count, 0)
            return dd.logger.warnLog?.message
        }

        let randomCommand = RUMCommandMock(time: Date(), canStartBackgroundView: false)
        let randomCommandLog = try XCTUnwrap(recordWarningOnReceiving(command: randomCommand))
        XCTAssertEqual(
            randomCommandLog,
            """
            \(String(describing: randomCommand)) was detected, but no view is active. To track views automatically, configure
            `RUM.Configuration.uiKitViewsPredicate` or use `.trackRUMView()` modifier in SwiftUI. You can also track views manually
            with `RUMMonitor.shared().startView()` and `RUMMonitor.shared().stopView()`.
            """
        )
    }

    func testGivenAnotherSceneHasAnActiveView_whenCommandTargetsSceneWithoutAView_itLogsWarning() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        _ = scope.process(
            command: startViewCommand(identity: ViewIdentifier("view-B"), name: "View B", sceneIdentifier: sceneB),
            context: context,
            writer: writer
        )
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .custom,
                name: "Action from missing A",
                target: .scene(sceneA)
            ),
            context: context,
            writer: writer
        )

        XCTAssertNotNil(dd.logger.warnLog)
        XCTAssertTrue(writer.events(ofType: RUMActionEvent.self).isEmpty)
    }

    func testGivenSessionWithNoActiveScope_whenReceivingSilentCommand_itDoesNotLogWarning() throws {
        func recordWarningOnReceiving(command: RUMCommand) -> String? {
            // Given
            let scope: RUMSessionScope = .mockWith(
                parent: parent,
                startTime: Date()
            )
            XCTAssertEqual(scope.viewScopes.count, 0)

            let dd = DD.mockWith(logger: CoreLoggerMock())
            defer { dd.reset() }

            // When
            _ = scope.process(command: command, context: context, writer: writer)

            // Then
            XCTAssertEqual(scope.viewScopes.count, 0)
            return dd.logger.warnLog?.message
        }

        let silentCommands: [RUMCommand] = [
            RUMKeepSessionAliveCommand(time: Date(), attributes: [:]),
            RUMUpdatePerformanceMetric(metric: .flutterBuildTime, value: 1.0, time: Date(), attributes: [:])
        ]

        for command in silentCommands {
            let log = recordWarningOnReceiving(command: command)
            XCTAssertNil(log, "It shouldn't log warning when receiving silent command: \(command)")
        }
    }

    // MARK: - Feature Operation Integration Tests

    func testProcessesFeatureOperationCommand_DelegatesToManager() {
        // Given
        let command: RUMOperationStepVitalCommand = .mockAny()
        let scope: RUMSessionScope = .mockWith(parent: parent)

        // When
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(result)
    }

    // MARK: - App launch metrics

    func testWhenSessionScopeReceivesTTIDCommand_itIsProcessedAccordingly() {
        // Given
        let command: RUMTimeToInitialDisplayCommand = .mockAny()
        let scope: RUMSessionScope = .mockWith(parent: parent)

        // When
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(result)
    }

    func testWhenSessionScopeReceivesTTFDCommand_itIsProcessedAccordingly() {
        // Given
        let command: RUMTimeToFullDisplayCommand = .mockAny()
        let scope: RUMSessionScope = .mockWith(parent: parent)

        // When
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(result)
    }

    // MARK: - Timeseries collector lifecycle

    func testWhenSessionScopeIsCreated_itStartsTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()

        // When
        let _: RUMSessionScope = .mockWith(
            parent: parent,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        // Then
        XCTAssertEqual(collector.startCallCount, 1)
        XCTAssertEqual(collector.stopCallCount, 0)
    }

    func testWhenSessionExpiresDueToMaxDuration_itStopsTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        // When — push past the max session duration
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)
        _ = scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer)

        // Then
        XCTAssertEqual(collector.stopCallCount, 1)
    }

    func testWhenSessionExpiresDueToInactivity_itStopsTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        _ = scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer)

        // When — push past the session inactivity timeout
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)
        _ = scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer)

        // Then
        XCTAssertEqual(collector.stopCallCount, 1)
    }

    func testWhenSessionScopeStartsNewSession_itStartsCollectorWithCorrectSessionID() {
        // Given
        let collector = TimeseriesCollectorSpy()
        let applicationID = "test-app-id"

        // When
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            dependencies: .mockWith(
                rumApplicationID: applicationID,
                timeseriesCollector: collector
            )
        )

        // Then
        XCTAssertEqual(collector.startCallCount, 1)
        XCTAssertEqual(collector.lastStartedApplicationID, applicationID)
        XCTAssertNotNil(collector.lastStartedSessionID, "Session ID should be set")
        XCTAssertFalse(collector.lastStartedSessionID?.isEmpty ?? true)
        XCTAssertEqual(collector.lastStartedSessionType, .user)
    }

    func testWhenSessionIsNotSampled_itDoesNotStartTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()

        // When
        _ = RUMSessionScope.mockWith(
            parent: parent,
            dependencies: .mockWith(samplingRate: 0, timeseriesCollector: collector)
        )

        // Then
        XCTAssertEqual(collector.startCallCount, 0)
    }

    func testWhenSessionIsCreatedInBackground_itStartsThenPausesTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        let sessionStartTime = Date()
        var context = self.context
        context.applicationStateHistory = .mockAppInBackground(since: sessionStartTime)

        // When
        _ = RUMSessionScope.mockWith(
            parent: parent,
            startTime: sessionStartTime,
            context: context,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        // Then
        XCTAssertEqual(collector.startCallCount, 1)
        XCTAssertEqual(collector.pauseCallCount, 1)
    }

    func testWhenAppEntersBackground_itPausesTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        // When
        _ = scope.process(
            command: RUMHandleAppLifecycleEventCommand(time: currentTime, event: .didEnterBackground),
            context: context,
            writer: writer
        )

        // Then
        XCTAssertEqual(collector.pauseCallCount, 1)
        XCTAssertEqual(collector.resumeCallCount, 0)
    }

    func testWhenAppEntersForeground_itResumesTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        // When
        _ = scope.process(
            command: RUMHandleAppLifecycleEventCommand(time: currentTime, event: .willEnterForeground),
            context: context,
            writer: writer
        )

        // Then
        XCTAssertEqual(collector.resumeCallCount, 1)
        XCTAssertEqual(collector.pauseCallCount, 0)
    }
}

// MARK: - Test Helpers

private func storedWatchdogViewID(in featureScope: FeatureScopeMock) throws -> String {
    let storedValue = try XCTUnwrap(
        featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.watchdogRUMViewEvent.rawValue)
    )
    let data = try XCTUnwrap(storedValue.data())
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let view = try XCTUnwrap(json["view"] as? [String: Any])
    return try XCTUnwrap(view["id"] as? String)
}

private class TimeseriesCollectorSpy: TimeseriesCollecting {
    weak var activeContextReader: RUMActiveContextReader?
    var startCallCount = 0
    var pauseCallCount = 0
    var resumeCallCount = 0
    var stopCallCount = 0
    var lastStartedSessionID: String?
    var lastStartedApplicationID: String?
    var lastStartedSessionType: RUMSessionType?
    var lastStoppedSessionID: String?
    var lastPausedSessionID: String?
    var lastResumedSessionID: String?

    func start(sessionID: String, applicationID: String, sessionType: RUMSessionType) {
        startCallCount += 1
        lastStartedSessionID = sessionID
        lastStartedApplicationID = applicationID
        lastStartedSessionType = sessionType
    }

    func pause(sessionID: String) {
        pauseCallCount += 1
        lastPausedSessionID = sessionID
    }

    func resume(sessionID: String) {
        resumeCallCount += 1
        lastResumedSessionID = sessionID
    }

    func stop(sessionID: String) {
        stopCallCount += 1
        lastStoppedSessionID = sessionID
    }

    var noteActivityCallCount = 0
    var lastActivitySessionID: String?
    var lastActivityTime: Date?

    func noteActivity(sessionID: String, at time: Date) {
        noteActivityCallCount += 1
        lastActivitySessionID = sessionID
        lastActivityTime = time
    }

    var flushCallCount = 0

    func flush() {
        flushCallCount += 1
    }
}
