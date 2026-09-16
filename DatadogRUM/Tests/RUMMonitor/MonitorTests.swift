/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
#if os(iOS)
import UIKit
#endif
@_spi(Internal)
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

class MonitorTests: XCTestCase {
    private var featureScope: FeatureScope! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        featureScope = FeatureScopeMock(
            context: .mockWith(
                launchInfo: .mockWith(
                    launchReason: .userLaunch,
                    processLaunchDate: Date()
                )
            )
        )
    }

    func testWhenSessionIsSampled_itSetsRUMContextInCore() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: DateProviderMock()
        )

        // When
        monitor.startView(key: "foo")

        // Then
        let expectedContext = monitor.currentRUMContext
        var datadogContext: DatadogContext?
        featureScope.context { datadogContext = $0 }
        let rumContext = try XCTUnwrap(datadogContext?.additionalContext(ofType: RUMCoreContext.self))
        XCTAssertEqual(rumContext.applicationID, expectedContext.rumApplicationID)
        XCTAssertEqual(rumContext.sessionID, expectedContext.sessionID.toRUMDataFormat)
        XCTAssertEqual(rumContext.viewID, expectedContext.activeViewID?.toRUMDataFormat)
    }

    func testWhenSessionIsNotSampled_RUMCoreSampler_returnsFalse() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 0),
            dateProvider: DateProviderMock()
        )

        // When
        monitor.startView(key: "foo")

        // Then
        var context: DatadogContext?
        featureScope.context { context = $0 }
        let rumContext = try XCTUnwrap(context?.additionalContext(ofType: RUMCoreContext.self))
        XCTAssertFalse(rumContext.sessionSampler.isSampled)
    }

    func testGivenConcurrentScenes_itKeepsSynchronousContextSnapshotForEachScene() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        monitor.process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: ViewIdentifier("view-A"),
                name: "View A",
                path: "View A",
                globalAttributes: [:],
                attributes: [:],
                instrumentationType: .uikit,
                target: .scene(sceneA)
            )
        )
        dateProvider.now = dateProvider.now.addingTimeInterval(1)
        monitor.process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: ViewIdentifier("view-B"),
                name: "View B",
                path: "View B",
                globalAttributes: [:],
                attributes: [:],
                instrumentationType: .uikit,
                target: .scene(sceneB)
            )
        )

        let provider: RUMContextSnapshotProviding = monitor
        let contextA = try XCTUnwrap(provider.rumContextSnapshot(for: .scene(sceneA)))
        let contextB = try XCTUnwrap(provider.rumContextSnapshot(for: .scene(sceneB)))

        XCTAssertEqual(contextA.viewName, "View A")
        XCTAssertEqual(contextB.viewName, "View B")
        XCTAssertNotEqual(contextA.viewID, contextB.viewID)
        XCTAssertEqual(
            provider.rumContextSnapshot(for: .processRepresentative)?.viewID,
            contextB.viewID
        )
        XCTAssertEqual(
            provider.rumContextSnapshot(for: .scene(sceneA), at: dateProvider.now)?.viewID,
            contextA.viewID
        )
        XCTAssertNil(
            provider.rumContextSnapshot(for: .scene(sceneA), at: .distantFuture)
        )
    }

    func testGivenOperationStartedDuringSceneHandoff_itUsesThatSceneInsteadOfRepresentative() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        monitor.process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: ViewIdentifier("view-A"),
                name: "View A",
                path: "View A",
                globalAttributes: [:],
                attributes: [:],
                instrumentationType: .uikit,
                target: .scene(sceneA)
            )
        )
        monitor.process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: ViewIdentifier("view-B"),
                name: "View B",
                path: "View B",
                globalAttributes: [:],
                attributes: [:],
                instrumentationType: .uikit,
                target: .scene(sceneB)
            )
        )

        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startOperation(
                name: "load_note",
                operationKey: nil,
                attributes: [:],
                options: nil
            )
        }

        let featureScope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let operation = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMVitalOperationStepEvent.self).last)
        XCTAssertEqual(operation.view.url, "View A")
    }

    func testGivenExplicitOperationScene_itOverridesInferredSceneAndRepresentative() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(
            in: monitor,
            dateProvider: dateProvider
        )

        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneB.rawValue) {
            monitor.startOperation(
                name: "thread_open",
                operationKey: "key-123",
                attributes: [:],
                options: nil,
                explicitTarget: .scene(sceneA)
            )
        }

        let featureScope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let operation = try XCTUnwrap(
            featureScope.eventsWritten(ofType: RUMVitalOperationStepEvent.self).last
        )
        XCTAssertEqual(operation.view.url, "View A")
    }

    func testGivenExplicitOperationSceneHasNoView_itUsesTrustworthyInferredSceneBeforeSnapshotAndRepresentative() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(
            in: monitor,
            dateProvider: dateProvider
        )

        monitor.startOperation(
            name: "thread_open",
            operationKey: "key-123",
            attributes: [:],
            options: nil,
            explicitTarget: .scene(sceneA)
        )
        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.addAction(type: .custom, name: "make A representative", attributes: [:])
        }
        XCTAssertEqual(
            monitor.rumContextSnapshot(for: .processRepresentative)?.viewName,
            "View A"
        )

        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneB.rawValue) {
            monitor.succeedOperation(
                name: "thread_open",
                operationKey: "key-123",
                attributes: [:],
                explicitTarget: .scene(
                    RUMSceneIdentifier(rawValue: "missing-scene")
                )
            )
        }

        let featureScope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let operations = featureScope.eventsWritten(ofType: RUMVitalOperationStepEvent.self)
        XCTAssertEqual(operations.map(\.view.url), ["View A", "View B"])
    }

    func testGivenManualActionsDuringSceneHandoff_theyUseThatSceneInsteadOfRepresentative() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let contextA = try XCTUnwrap(
            monitor.rumContextSnapshot(for: .scene(sceneA))
        )

        monitor.addAction(type: .custom, name: "representative-action", attributes: [:])
        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.addAction(type: .custom, name: "scene-action", attributes: [:])
            monitor.startAction(type: .custom, name: "scene-continuous-action", attributes: [:])
            dateProvider.now = dateProvider.now.addingTimeInterval(1)
            monitor.stopAction(type: .custom, name: "scene-continuous-action", attributes: [:])
        }
        RUMContextHandoff.withValue(rumContext: contextA, sceneIdentifier: sceneB.rawValue) {
            monitor.addAction(type: .custom, name: "exact-view-action", attributes: [:])
        }

        let featureScope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let actions = featureScope.eventsWritten(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.map(\.action.target?.name), [
            "representative-action",
            "scene-action",
            "scene-continuous-action",
            "exact-view-action"
        ])
        XCTAssertEqual(actions.map(\.view.url), ["View B", "View A", "View A", "View A"])
    }

    func testGivenManualErrorsDuringSceneHandoff_theyUseExactOrSceneContext() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)

        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startAction(type: .tap, name: "Tap A", attributes: [:])
        }
        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneB.rawValue) {
            monitor.startAction(type: .tap, name: "Tap B", attributes: [:])
        }
        let contextA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let contextB = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))

        RUMContextHandoff.withValue(rumContext: contextA, sceneIdentifier: sceneB.rawValue) {
            monitor.addError(
                message: "exact A error",
                type: nil,
                stack: nil,
                source: .source,
                attributes: [:],
                file: nil,
                line: nil
            )
        }
        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.addError(error: ErrorMock("scene A error"), source: .source, attributes: [:])
        }
        var didComplete = false
        RUMContextHandoff.withValue(rumContext: contextA, sceneIdentifier: sceneB.rawValue) {
            monitor.addError(
                error: ErrorMock("completion A error"),
                source: .source,
                attributes: [:],
                completionHandler: { didComplete = true }
            )
        }
        monitor.addError(
            message: "representative B error",
            type: nil,
            stack: nil,
            source: RUMInternalErrorSource.source,
            attributes: [:]
        )

        let featureScope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let errors = featureScope.eventsWritten(ofType: RUMErrorEvent.self)
        XCTAssertEqual(errors.map(\.view.url), ["View A", "View A", "View A", "View B"])
        let actionIDs: [RUMActionID?] = errors.map { $0.action?.id }
        let actionAID = contextA.userActionID.map { RUMActionID.string(value: $0) }
        let actionBID = contextB.userActionID.map { RUMActionID.string(value: $0) }
        XCTAssertEqual(actionIDs, [
            actionAID,
            actionAID,
            actionAID,
            actionBID
        ])
        XCTAssertTrue(didComplete)
    }

    func testGivenViewMutationsDuringSceneHandoff_theyOnlyUpdateThatView() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let contextA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        dateProvider.now = dateProvider.now.addingTimeInterval(1)

        RUMContextHandoff.withValue(rumContext: contextA, sceneIdentifier: sceneB.rawValue) {
            monitor.addViewAttribute(forKey: "exact", value: "A")
            monitor.addViewAttributes([
                "batch": "A",
                "remove-one": true,
                "remove-many": true
            ])
            monitor.addTiming(name: "timing-A")
            monitor.addViewLoadingTime(overwrite: false)
            monitor.addFeatureFlagEvaluation(name: "flag-A", value: "A")
        }
        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.removeViewAttribute(forKey: "remove-one")
            monitor.removeViewAttributes(forKeys: ["remove-many"])
        }

        monitor.addViewAttribute(forKey: "representative", value: "B")
        monitor.addTiming(name: "timing-B")
        monitor.addViewLoadingTime(overwrite: false)
        monitor.addFeatureFlagEvaluation(name: "flag-B", value: "B")

        let session = try XCTUnwrap(monitor.applicationScope.activeSession)
        let viewA = try XCTUnwrap(session.viewScopes.first { $0.sceneIdentifier == sceneA })
        let viewB = try XCTUnwrap(session.viewScopes.first { $0.sceneIdentifier == sceneB })
        XCTAssertEqual(viewA.attributes["exact"] as? String, "A")
        XCTAssertEqual(viewA.attributes["batch"] as? String, "A")
        XCTAssertNil(viewA.attributes["remove-one"])
        XCTAssertNil(viewA.attributes["remove-many"])
        XCTAssertNil(viewA.attributes["representative"])
        XCTAssertEqual(viewB.attributes["representative"] as? String, "B")
        XCTAssertNil(viewB.attributes["exact"])
        XCTAssertNotNil(viewA.customTimings["timing-A"])
        XCTAssertNil(viewA.customTimings["timing-B"])
        XCTAssertNotNil(viewB.customTimings["timing-B"])
        XCTAssertNil(viewB.customTimings["timing-A"])
        XCTAssertNotNil(viewA.viewLoadingTime)
        XCTAssertNotNil(viewB.viewLoadingTime)
        XCTAssertEqual(viewA.featureFlags["flag-A"] as? String, "A")
        XCTAssertNil(viewA.featureFlags["flag-B"])
        XCTAssertEqual(viewB.featureFlags["flag-B"] as? String, "B")
        XCTAssertNil(viewB.featureFlags["flag-A"])
    }

    func testGivenMatchingManualViewKeysInTwoScenes_whenAStopsAndReturns_itKeepsIndependentOccurrences() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startView(key: "Home", name: "Home A", attributes: [:])
        }
        let firstA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneB.rawValue) {
            monitor.startView(key: "Home", name: "Home B", attributes: [:])
        }
        let firstB = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        XCTAssertNotEqual(firstA.viewID, firstB.viewID)

        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.stopView(key: "Home", attributes: [:])
        }
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID, firstB.viewID)

        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startView(key: "Home", name: "Home A", attributes: [:])
        }
        let returnedA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        XCTAssertNotEqual(returnedA.viewID, firstA.viewID)
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID, firstB.viewID)
    }

    func testGivenExactViewAndContradictoryScene_whenStartingManualView_itUsesExactViewsScene() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let contextA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let contextB = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))

        RUMContextHandoff.withValue(rumContext: contextA, sceneIdentifier: sceneB.rawValue) {
            monitor.startView(key: "detail", name: "Detail A", attributes: [:])
        }

        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneA))?.viewName, "Detail A")
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID, contextB.viewID)
    }

    #if os(iOS)
    func testGivenUnattachedViewController_whenStartedDuringSceneHandoff_itUsesThatScene() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)

        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startView(viewController: UIViewController(), name: "Controller A", attributes: [:])
        }
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneA))?.viewName, "Controller A")

        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneB.rawValue) {
            monitor.addAction(type: .custom, name: "Represent B", attributes: [:])
        }
        monitor.startView(viewController: UIViewController(), name: "Representative Controller", attributes: [:])
        XCTAssertEqual(
            monitor.rumContextSnapshot(for: .scene(sceneB))?.viewName,
            "Representative Controller"
        )
    }
    #endif

    func testGivenManualResourcesStartedDuringSceneHandoff_theyCompleteOnThatScene() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, _) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let resourceURL = URL(string: "https://example.com/scene-resource")!

        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startResource(resourceKey: "url-resource", url: resourceURL, attributes: [:])
            monitor.startResource(
                resourceKey: "request-resource",
                request: URLRequest(url: resourceURL),
                attributes: [:]
            )
            monitor.startResource(
                resourceKey: "url-string-resource",
                httpMethod: .get,
                urlString: resourceURL.absoluteString,
                attributes: [:]
            )
        }
        ["url-resource", "request-resource", "url-string-resource"].forEach { resourceKey in
            dateProvider.now = dateProvider.now.addingTimeInterval(1)
            monitor.stopResource(
                resourceKey: resourceKey,
                statusCode: 200,
                kind: .native,
                size: 1,
                attributes: [:]
            )
        }

        monitor.startResource(resourceKey: "representative-resource", url: resourceURL, attributes: [:])
        dateProvider.now = dateProvider.now.addingTimeInterval(1)
        monitor.stopResource(
            resourceKey: "representative-resource",
            statusCode: 200,
            kind: .native,
            size: 1,
            attributes: [:]
        )

        let featureScope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let resources = featureScope.eventsWritten(ofType: RUMResourceEvent.self)
        XCTAssertEqual(resources.map(\.resource.url), Array(repeating: resourceURL.absoluteString, count: 4))
        XCTAssertEqual(resources.map(\.view.url), ["View A", "View A", "View A", "View B"])
    }

    #if !os(watchOS)
    func testStartView_withViewController_itUsesClassNameAsViewName() throws {
        // Given
        let vc = createMockView(viewControllerClassName: "SomeViewController")

        // When
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: DateProviderMock()
        )
        monitor.startView(viewController: vc)

        // Then
        XCTAssertEqual(monitor.applicationScope.sessionScopes.first?.viewScopes.first?.viewName, "SomeViewController")
        XCTAssertEqual(monitor.applicationScope.sessionScopes.first?.viewScopes.first?.viewPath, "SomeViewController")
    }

    func testStartView_withViewController_itUsesClassNameAsViewPath() throws {
        // Given
        let vc = createMockView(viewControllerClassName: "SomeViewController")

        // When
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: DateProviderMock()
        )
        monitor.startView(viewController: vc, name: "Some View")

        // Then
        XCTAssertEqual(monitor.applicationScope.sessionScopes.first?.viewScopes.first?.viewName, "Some View")
        XCTAssertEqual(monitor.applicationScope.sessionScopes.first?.viewScopes.first?.viewPath, "SomeViewController")
    }
    #endif

    // MARK: - App launch

    func testReportTTIDAndTTFD_thenTheyAreWrittenAsVitalEvents() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()

        // When
        monitor.process(command: RUMTimeToInitialDisplayCommand(time: Date()))
        monitor.reportAppFullyDisplayed()

        // Then
        let vitalEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMVitalAppLaunchEvent.self)

        XCTAssertEqual(vitalEvents?.count, 2)
        XCTAssertEqual(vitalEvents?.first?.vital.appLaunchMetric, .ttid)
        XCTAssertEqual(vitalEvents?.last?.vital.appLaunchMetric, .ttfd)
    }

    func testReportTTFDWithoutTTID_thenTheyAreNotWritten() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()

        // When
        monitor.reportAppFullyDisplayed()

        // Then
        let vitalEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMVitalAppLaunchEvent.self)

        XCTAssertEqual(vitalEvents?.count, 0)
    }

    func testReportTTIDWithoutTTFD_thenTTIDIsWrittenAsVitalEvent() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()

        // When
        monitor.process(command: RUMTimeToInitialDisplayCommand(time: Date()))

        // Then
        let vitalEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMVitalAppLaunchEvent.self)

        XCTAssertEqual(vitalEvents?.count, 1)
        XCTAssertEqual(vitalEvents?.first?.vital.appLaunchMetric, .ttid)
    }

    // MARK: - View Loading Time

    func testAddViewLoadingTimeToActiveView_thenLoadingTimeUpdated() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()
        monitor.startView(key: "ActiveView")

        // When
        monitor.addViewLoadingTime(overwrite: false)

        // Then
        let viewEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "ActiveView" }
        let lastView = try XCTUnwrap(viewEvents?.last)

        XCTAssertNotNil(lastView.view.loadingTime)
        XCTAssertTrue(lastView.view.loadingTime! > 0)
    }

    func testAddViewLoadingTimeNoActiveView_thenNoEvent() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()
        monitor.startView(key: "InactiveView")
        monitor.stopView(key: "InactiveView")

        // When
        monitor.addViewLoadingTime(overwrite: false)

        // Then
        let viewEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "InactiveView" }
        XCTAssertNil(viewEvents?.last?.view.loadingTime)
    }

    func testAddViewLoadingTimeMultipleTimes_thenLoadingTimeOverwritten() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()
        monitor.startView(key: "ActiveView")

        // When
        monitor.addViewLoadingTime(overwrite: false)

        // Then
        let viewEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "ActiveView" }
        let lastView = try XCTUnwrap(viewEvents?.last)

        XCTAssertNotNil(lastView.view.loadingTime)
        XCTAssertTrue(lastView.view.loadingTime! > 0)

        let old = lastView.view.loadingTime!

        // When
        monitor.addViewLoadingTime(overwrite: false)

        // Then
        let viewEvents2 = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "ActiveView" }
        let lastView2 = try XCTUnwrap(viewEvents2?.last)

        XCTAssertNotNil(lastView2.view.loadingTime)
        XCTAssertTrue(lastView2.view.loadingTime! > 0)

        XCTAssertEqual(lastView2.view.loadingTime!, old)

        // When
        monitor.addViewLoadingTime(overwrite: true)

        // Then
        let viewEvents3 = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "ActiveView" }
        let lastView3 = try XCTUnwrap(viewEvents3?.last)

        XCTAssertNotNil(lastView3.view.loadingTime)
        XCTAssertTrue(lastView3.view.loadingTime! > 0)

        XCTAssertTrue(lastView3.view.loadingTime! > old)
    }

    // MARK: - hasReplay snapshot

    func testHasReplaySnapshot_isGatedByTimeseriesCollectorAndResetOnNewSession() throws {
        let dateProvider = DateProviderMock()
        featureScope = FeatureScopeMock(
            context: .mockWith(additionalContext: [SessionReplayCoreContext.HasReplay(value: true)])
        )

        // Given — no timeseries collector configured
        let monitorWithoutCollector = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: dateProvider
        )

        // When
        monitorWithoutCollector.startView(key: "foo")

        // Then — the snapshot is never updated
        XCTAssertNil((monitorWithoutCollector as RUMActiveContextReader).hasReplay)

        // Given — a timeseries collector configured
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, timeseriesCollector: TimeseriesCollectorStub()),
            dateProvider: dateProvider
        )
        let activeContextReader: RUMActiveContextReader = monitor

        monitor.startView(key: "foo")
        XCTAssertEqual(activeContextReader.hasReplay, true)

        // When — the session expires (starting a new one within a single `process(command:)` call) while
        // the context still carries the previous session's (now stale) `hasReplay` value
        dateProvider.now = dateProvider.now.addingTimeInterval(4 * 60 * 60 + 1) // exceeds session max duration
        monitor.startView(key: "bar")

        // Then — the stale value is not carried over into the new session
        XCTAssertNil(activeContextReader.hasReplay)
    }
}

private extension MonitorTests {
    func startConcurrentSceneViews(
        in monitor: Monitor,
        dateProvider: DateProviderMock
    ) -> (sceneA: RUMSceneIdentifier, sceneB: RUMSceneIdentifier) {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        monitor.process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: ViewIdentifier("view-A"),
                name: "View A",
                path: "View A",
                globalAttributes: [:],
                attributes: [:],
                instrumentationType: .uikit,
                target: .scene(sceneA)
            )
        )
        monitor.process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: ViewIdentifier("view-B"),
                name: "View B",
                path: "View B",
                globalAttributes: [:],
                attributes: [:],
                instrumentationType: .uikit,
                target: .scene(sceneB)
            )
        )

        return (sceneA, sceneB)
    }
}

private class TimeseriesCollectorStub: TimeseriesCollecting {
    weak var activeContextReader: RUMActiveContextReader?
    func start(sessionID: String, applicationID: String, sessionType: RUMSessionType) {}
    func pause(sessionID: String) {}
    func resume(sessionID: String) {}
    func stop(sessionID: String) {}
    func noteActivity(sessionID: String, at time: Date) {}
    func flush() {}
}

// MARK: - Convenience

private extension Monitor {
    /// Returns RUM context assuming that some view is started.
    var currentRUMContext: RUMContext { applicationScope.activeSession!.viewScopes.last!.context }
}
