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
@testable import DatadogInternal
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
        XCTAssertEqual(provider.rumContextSnapshot(for: .scene(sceneA), at: nil)?.viewID, contextA.viewID)
        dateProvider.now = .distantFuture
        XCTAssertNil(provider.rumContextSnapshot(for: .scene(sceneA), at: nil))
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

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
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

    private enum ResourceStartForm: CaseIterable {
        case request, url, method
    }

    private func startTargetedResource(
        in monitor: Monitor,
        form: ResourceStartForm,
        key: String,
        target: RUMCommandTarget
    ) {
        let url = URL(string: "https://example.com/resource")!
        let attributes: [AttributeKey: AttributeValue] = ["start": "selected"]
        switch form {
        case .request:
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            monitor.startResource(resourceKey: key, request: request, attributes: attributes, explicitTarget: target)
        case .url:
            monitor.startResource(resourceKey: key, url: url, attributes: attributes, explicitTarget: target)
        case .method:
            monitor.startResource(resourceKey: key, httpMethod: .put, urlString: url.absoluteString, attributes: attributes, explicitTarget: target)
        }
    }

    func testExplicitResourceStartOverridesInferredSceneForAllForms() throws {
        for form in ResourceStartForm.allCases {
            let dateProvider = DateProviderMock()
            let monitor = Monitor(
                dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
                dateProvider: dateProvider
            )
            let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
            let owner = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
            RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneB.rawValue) {
                startTargetedResource(in: monitor, form: form, key: "targeted", target: .scene(sceneA))
            }
            XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewName, "View B")
            monitor.stopResource(resourceKey: "targeted", statusCode: 201, kind: .native, size: 55, attributes: ["stop": "original"])

            let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
            let event = try XCTUnwrap(scope.eventsWritten(ofType: RUMResourceEvent.self).last)
            XCTAssertEqual(event.view.id, owner.viewID, "Form: \(form)")
            XCTAssertEqual(event.session.id, owner.sessionID)
            XCTAssertEqual(event.resource.url, "https://example.com/resource")
            XCTAssertEqual(event.resource.method?.rawValue, form == .request ? "POST" : form == .url ? "GET" : "PUT")
            XCTAssertEqual(event.context?.contextInfo["start"] as? String, "selected")
            XCTAssertEqual(event.context?.contextInfo["stop"] as? String, "original")
        }
    }

    func testExplicitResourceStartKeepsOwnerAfterNavigationAndPeerAction() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let owner = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        startTargetedResource(in: monitor, form: .request, key: "targeted", target: .scene(sceneA))
        monitor.process(command: RUMStartViewCommand.mockWith(
            time: dateProvider.now, identity: ViewIdentifier("next-A"), name: "Next A", target: .scene(sceneA)
        ))
        monitor.startAction(type: .tap, name: "Peer", attributes: [:], explicitTarget: .scene(sceneB))
        monitor.stopResourceWithError(resourceKey: "targeted", message: "Expected failure", type: "Fixture", response: nil, attributes: [:])
        monitor.stopAction(type: .tap, name: nil, attributes: [:], explicitTarget: .scene(sceneB))

        let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let error = try XCTUnwrap(scope.eventsWritten(ofType: RUMErrorEvent.self).last)
        let action = try XCTUnwrap(scope.eventsWritten(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(error.view.id, owner.viewID)
        XCTAssertEqual(error.session.id, owner.sessionID)
        XCTAssertEqual(action.action.error?.count, 0)
        XCTAssertEqual(action.action.resource?.count, 0)
    }

    func testUnavailableResourceTargetPreservesInferenceAndRepresentativeForAllForms() throws {
        for form in ResourceStartForm.allCases {
            let dateProvider = DateProviderMock()
            let monitor = Monitor(
                dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
                dateProvider: dateProvider
            )
            let (sceneA, _) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
            let target = RUMCommandTarget.scene(RUMSceneIdentifier(rawValue: "missing"))
            RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
                startTargetedResource(in: monitor, form: form, key: "inferred", target: target)
            }
            startTargetedResource(in: monitor, form: form, key: "representative", target: target)
            monitor.stopResource(resourceKey: "inferred", kind: .native)
            monitor.stopResource(resourceKey: "representative", kind: .native)
            let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
            XCTAssertEqual(scope.eventsWritten(ofType: RUMResourceEvent.self).suffix(2).map(\.view.name), ["View A", "View B"])
        }
    }

    func testExplicitResourceStartOverridesExactInferenceAndResolvesCurrentView() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let contextB = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        let oldA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        startTargetedResource(in: monitor, form: .url, key: "reused", target: .scene(sceneA))
        monitor.stopResource(resourceKey: "reused", kind: .native)
        monitor.process(command: RUMStartViewCommand.mockWith(
            time: dateProvider.now, identity: ViewIdentifier("next-A"), name: "Next A", target: .scene(sceneA)
        ))
        let newA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: contextB, sceneIdentifier: sceneB.rawValue) {
            startTargetedResource(in: monitor, form: .url, key: "reused", target: .scene(sceneA))
        }
        monitor.stopResource(resourceKey: "reused", kind: .native)
        let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let events = scope.eventsWritten(ofType: RUMResourceEvent.self)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.view.id), [oldA.viewID, newA.viewID])
        XCTAssertNotEqual(oldA.viewID, newA.viewID)
    }

    func testExplicitResourceStartAfterSessionExpirationUsesFreshTargetScene() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
        let (sceneA, _) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let oldA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        dateProvider.now = dateProvider.now.addingTimeInterval(4 * 60 * 60 + 1)
        startTargetedResource(in: monitor, form: .url, key: "expired", target: .scene(sceneA))
        monitor.stopResource(resourceKey: "expired", kind: .native)
        let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let event = try XCTUnwrap(scope.eventsWritten(ofType: RUMResourceEvent.self).last)
        XCTAssertEqual(event.view.name, "View A")
        XCTAssertNotEqual(event.view.id, oldA.viewID)
        XCTAssertNotEqual(event.session.id, oldA.sessionID)
        XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewName, "View B")
    }

    func testResourceSessionRestorationPreservesRepresentativeWithoutExplicitTarget() throws {
        for delayed in [false, true] {
            let dateProvider = DateProviderMock()
            let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
            _ = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
            dateProvider.now = dateProvider.now.addingTimeInterval(4 * 60 * 60 + 1)
            if delayed {
                monitor.process(command: RUMHandleAppLifecycleEventCommand(time: dateProvider.now, event: .willEnterForeground))
            }
            monitor.startResource(resourceKey: "legacy", url: URL(string: "https://example.com/legacy")!, attributes: [:])
            monitor.stopResource(resourceKey: "legacy", kind: .native)
            let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
            let event = try XCTUnwrap(scope.eventsWritten(ofType: RUMResourceEvent.self).last)
            XCTAssertEqual(event.view.name, "View B", "Delayed boundary: \(delayed)")
            XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewName, "View B")
        }
    }

    func testExplicitResourceStartDoesNotRestoreViewsAfterSessionStop() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
        let (sceneA, _) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        monitor.stopSession()
        startTargetedResource(in: monitor, form: .url, key: "stopped", target: .scene(sceneA))
        monitor.stopResource(resourceKey: "stopped", kind: .native)
        let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        XCTAssertTrue(scope.eventsWritten(ofType: RUMResourceEvent.self).isEmpty)
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
    }

    func testResourceMetricsAndCompletionRetainExplicitOwnerAfterViewStop() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
        let (sceneA, _) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let owner = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        startTargetedResource(in: monitor, form: .url, key: "disconnected", target: .scene(sceneA))
        monitor.process(command: RUMStopViewCommand.mockWith(
            time: dateProvider.now, identity: ViewIdentifier("view-A"), target: .scene(sceneA)
        ))
        monitor.addResourceMetrics(resourceKey: "disconnected", metrics: .mockAny(), attributes: ["metrics": "owner"])
        monitor.stopResource(resourceKey: "disconnected", kind: .native)
        startTargetedResource(in: monitor, form: .url, key: "closed-target", target: .scene(sceneA))
        monitor.stopResource(resourceKey: "closed-target", kind: .native)
        let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let events = scope.eventsWritten(ofType: RUMResourceEvent.self)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.view.id, owner.viewID)
        XCTAssertEqual(events.first?.session.id, owner.sessionID)
        XCTAssertEqual(events.first?.context?.contextInfo["metrics"] as? String, "owner")
        XCTAssertEqual(events.last?.view.name, "View B")
    }

    func testURLSessionCapturedResourceKeepsOwnerAcrossSessionStopAndPeerActions() throws {
        for completion in 0...2 {
            let fails = completion != 0
            let featureScope = FeatureScopeMock(context: .mockWith(
                launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: Date())
            ))
            let dateProvider = DateProviderMock()
            let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
            let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
            let owner = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
            let handler = URLSessionRUMResourcesHandler(
                dateProvider: dateProvider,
                rumAttributesProvider: { _, _, _, _ in ["automatic": "owner"] },
                distributedTracing: nil,
                headerProcessor: nil,
                disallowList: nil,
                telemetry: NOPTelemetry()
            )
            handler.publish(to: monitor)
            let (request, _, state) = handler.modify(
                request: URLRequest(url: URL(string: "https://example.com/automatic")!),
                headerTypes: [],
                networkContext: NetworkContext(rumContext: owner)
            )
            let interception = URLSessionTaskInterception(
                request: ImmutableRequest(request: request), isFirstParty: false, trackingMode: .automatic
            )
            handler.interceptionDidStart(interception: interception, capturedStates: [try XCTUnwrap(state)])
            monitor.stopSession()
            _ = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
            monitor.startAction(type: .tap, name: "New B", attributes: [:], explicitTarget: .scene(sceneB))
            let metrics = ResourceMetrics.mockWith(
                fetch: .init(start: dateProvider.now, end: dateProvider.now.addingTimeInterval(0.2)),
                responseBodySize: (encoded: 25, decoded: 50)
            )
            interception.register(metrics: metrics)
            interception.register(
                response: completion == 1 ? nil : HTTPURLResponse.mockResponseWith(statusCode: 200),
                error: fails ? ErrorMock() : nil
            )
            handler.interceptionDidComplete(interception: interception)
            handler.interceptionDidComplete(interception: interception)
            monitor.stopAction(type: .tap, name: nil, attributes: [:], explicitTarget: .scene(sceneB))

            let scope = featureScope
            let action = try XCTUnwrap(scope.eventsWritten(ofType: RUMActionEvent.self).last)
            XCTAssertEqual(action.action.resource?.count, 0)
            XCTAssertEqual(action.action.error?.count, 0)
            if fails {
                let errors = scope.eventsWritten(ofType: RUMErrorEvent.self)
                XCTAssertEqual(errors.count, 1)
                XCTAssertTrue(scope.eventsWritten(ofType: RUMResourceEvent.self).isEmpty)
                XCTAssertEqual(errors.last?.error.resource?.statusCode, completion == 2 ? 200 : 0)
                XCTAssertEqual(errors.last?.view.id, owner.viewID)
                XCTAssertEqual(errors.last?.session.id, owner.sessionID)
                XCTAssertEqual(errors.last?.context?.contextInfo["automatic"] as? String, "owner")
            } else {
                let resources = scope.eventsWritten(ofType: RUMResourceEvent.self)
                XCTAssertEqual(resources.count, 1)
                XCTAssertEqual(resources.last?.view.id, owner.viewID)
                XCTAssertEqual(resources.last?.session.id, owner.sessionID)
                XCTAssertEqual(resources.last?.context?.contextInfo["automatic"] as? String, "owner")
                XCTAssertEqual(resources.last?.resource.size, 50)
                XCTAssertEqual(resources.last?.resource.duration, metrics.fetch.duration.dd.toInt64Nanoseconds)
            }
        }
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

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneB.rawValue) {
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
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.addAction(type: .custom, name: "make A representative", attributes: [:])
        }
        XCTAssertEqual(
            monitor.rumContextSnapshot(for: .processRepresentative)?.viewName,
            "View A"
        )

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneB.rawValue) {
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
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.addAction(type: .custom, name: "scene-action", attributes: [:])
            monitor.startAction(type: .custom, name: "scene-continuous-action", attributes: [:])
            dateProvider.now = dateProvider.now.addingTimeInterval(1)
            monitor.stopAction(type: .custom, name: "scene-continuous-action", attributes: [:])
        }
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: contextA, sceneIdentifier: sceneB.rawValue) {
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

    func testGivenExplicitActionScene_itOverridesInferredSceneAndRepresentative() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(
            in: monitor,
            dateProvider: dateProvider
        )

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneB.rawValue) {
            monitor.addAction(
                type: .custom,
                name: "explicit A",
                attributes: [:],
                explicitTarget: .scene(sceneA)
            )
        }

        let featureScope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let action = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(action.action.target?.name, "explicit A")
        XCTAssertEqual(action.view.url, "View A")
        XCTAssertEqual(
            monitor.rumContextSnapshot(for: .processRepresentative)?.viewName,
            "View A"
        )
    }

    func testGivenExplicitActionSceneHasNoView_itUsesTrustworthyInferredScene() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(
            in: monitor,
            dateProvider: dateProvider
        )

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.addAction(type: .custom, name: "represent A", attributes: [:])
        }
        XCTAssertEqual(
            monitor.rumContextSnapshot(for: .processRepresentative)?.viewName,
            "View A"
        )

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneB.rawValue) {
            monitor.addAction(
                type: .custom,
                name: "inferred B",
                attributes: [:],
                explicitTarget: .scene(RUMSceneIdentifier(rawValue: "missing-scene"))
            )
        }

        let featureScope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let actions = featureScope.eventsWritten(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.suffix(2).map(\.view.url), ["View A", "View B"])
        XCTAssertEqual(
            monitor.rumContextSnapshot(for: .processRepresentative)?.viewName,
            "View B"
        )
    }

    func testGivenExplicitContinuousActions_theyOverrideContradictoryInferenceAndStopIndependently() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let contextB = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: contextB, sceneIdentifier: sceneB.rawValue) {
            monitor.startAction(type: .custom, name: "same", attributes: ["start": "A"], explicitTarget: .scene(sceneA))
        }
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startAction(type: .custom, name: "same", attributes: ["start": "B"], explicitTarget: .scene(sceneB))
        }
        dateProvider.now = dateProvider.now.addingTimeInterval(1)
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.stopAction(type: .swipe, name: "finished B", attributes: ["stop": "B"], explicitTarget: .scene(sceneB))
            // B is a valid view even though its action slot is now empty.
            monitor.stopAction(type: .custom, name: "must not stop A", attributes: [:], explicitTarget: .scene(sceneB))
        }
        let session = try XCTUnwrap(monitor.applicationScope.activeSession)
        XCTAssertNotNil(session.viewScopes.first { $0.sceneIdentifier == sceneA }?.userActionScope)
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: contextB, sceneIdentifier: sceneB.rawValue) {
            monitor.stopAction(type: .tap, name: "finished A", attributes: ["stop": "A"], explicitTarget: .scene(sceneA))
        }

        let actions = try XCTUnwrap(featureScope as? FeatureScopeMock).eventsWritten(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.map(\.view.url), ["View B", "View A"])
        XCTAssertEqual(actions.map(\.action.target?.name), ["finished B", "finished A"])
        XCTAssertEqual(actions.map(\.action.type), [.swipe, .tap])
        XCTAssertEqual(actions.map { $0.context?.contextInfo["start"] as? String }, ["B", "A"])
        XCTAssertEqual(actions.map { $0.context?.contextInfo["stop"] as? String }, ["B", "A"])
        XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewName, "View A")
    }

    func testGivenUnavailableContinuousActionTarget_itPreservesInferenceThenRepresentative() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, _) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let contextA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let unavailable = RUMCommandTarget.scene(RUMSceneIdentifier(rawValue: "closed-scene"))
        monitor.startAction(type: .custom, name: "representative B", attributes: [:], explicitTarget: unavailable)
        monitor.stopAction(type: .custom, name: nil, attributes: [:], explicitTarget: unavailable)
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: contextA, sceneIdentifier: "contradictory-scene") {
            monitor.startAction(type: .custom, name: "exact A", attributes: [:], explicitTarget: unavailable)
            monitor.stopAction(type: .custom, name: nil, attributes: [:], explicitTarget: unavailable)
        }
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startAction(type: .custom, name: "scene A", attributes: [:], explicitTarget: unavailable)
            monitor.stopAction(type: .custom, name: nil, attributes: [:], explicitTarget: unavailable)
        }
        let actions = try XCTUnwrap(featureScope as? FeatureScopeMock).eventsWritten(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.map(\.view.url), ["View B", "View A", "View A"])
        XCTAssertEqual(actions.map(\.action.target?.name), ["representative B", "exact A", "scene A"])
    }

    func testGivenTargetedContinuousActions_duplicateStartAndNavigationKeepPeerAction() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        monitor.startAction(type: .custom, name: "original A", attributes: [:], explicitTarget: .scene(sceneA))
        monitor.startAction(type: .custom, name: "duplicate A", attributes: [:], explicitTarget: .scene(sceneA))
        monitor.startAction(type: .custom, name: "original B", attributes: [:], explicitTarget: .scene(sceneB))
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startView(key: "next-A", name: "Next A")
        }
        let session = try XCTUnwrap(monitor.applicationScope.activeSession)
        XCTAssertNotNil(session.viewScopes.first { $0.sceneIdentifier == sceneB }?.userActionScope)
        monitor.startAction(type: .custom, name: "next action A", attributes: [:], explicitTarget: .scene(sceneA))
        monitor.stopAction(type: .custom, name: nil, attributes: [:], explicitTarget: .scene(sceneA))
        monitor.stopAction(type: .custom, name: nil, attributes: [:], explicitTarget: .scene(sceneB))
        let actions = try XCTUnwrap(featureScope as? FeatureScopeMock).eventsWritten(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.map(\.view.url), ["View A", "next-A", "View B"])
        XCTAssertEqual(actions.map(\.action.target?.name), ["original A", "next action A", "original B"])
    }

    func testGivenExpiredContinuousAction_peerStopDoesNotContaminateItsAttributes() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        monitor.startAction(type: .custom, name: "expires A", attributes: ["owner": "A"], explicitTarget: .scene(sceneA))
        dateProvider.now = dateProvider.now.addingTimeInterval(9)
        monitor.startAction(type: .custom, name: "stops B", attributes: ["owner": "B"], explicitTarget: .scene(sceneB))
        dateProvider.now = dateProvider.now.addingTimeInterval(2)
        monitor.stopAction(type: .custom, name: nil, attributes: ["completion": "B"], explicitTarget: .scene(sceneB))
        let actions = try XCTUnwrap(featureScope as? FeatureScopeMock).eventsWritten(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.map(\.action.target?.name), ["expires A", "stops B"])
        XCTAssertNil(actions.first?.context?.contextInfo["completion"])
        XCTAssertEqual(actions.last?.context?.contextInfo["completion"] as? String, "B")
    }

    func testExplicitCurrentViewErrorsOverrideInferenceForEveryForm() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        monitor.startAction(type: .tap, name: "A", attributes: [:], explicitTarget: .scene(sceneA))
        monitor.startAction(type: .tap, name: "B", attributes: [:], explicitTarget: .scene(sceneB))
        let owner = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let peer = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        var completions = 0
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: peer, sceneIdentifier: sceneB.rawValue) {
            monitor.addError(
                message: "message A",
                type: "MessageType",
                stack: "selected stack",
                source: .source,
                attributes: ["form": "message"],
                file: nil,
                line: nil,
                explicitTarget: .scene(sceneA)
            )
            monitor.addError(error: ErrorMock("error A"), source: .custom, attributes: ["form": "error"], explicitTarget: .scene(sceneA))
            monitor.addError(
                error: ErrorMock("callback A"),
                source: .custom,
                attributes: ["form": "callback"],
                completionHandler: { completions += 1 },
                explicitTarget: .scene(sceneA)
            )
        }
        let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let errors = scope.eventsWritten(ofType: RUMErrorEvent.self)
        XCTAssertEqual(errors.count, 3)
        XCTAssertEqual(errors.map(\.view.id), Array(repeating: owner.viewID, count: 3))
        XCTAssertEqual(errors.map(\.session.id), Array(repeating: owner.sessionID, count: 3))
        XCTAssertEqual(errors.map(\.action?.id), Array(repeating: owner.userActionID.map { RUMActionID.string(value: $0) }, count: 3))
        XCTAssertEqual(errors.first?.error.type, "MessageType")
        XCTAssertEqual(errors.first?.error.stack, "selected stack")
        XCTAssertEqual(errors.map { $0.context?.contextInfo["form"] as? String }, ["message", "error", "callback"])
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, peer.viewID)
        monitor.stopAction(type: .tap, name: nil, attributes: [:], explicitTarget: .scene(sceneA))
        monitor.stopAction(type: .tap, name: nil, attributes: [:], explicitTarget: .scene(sceneB))
        let actions = scope.eventsWritten(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.map(\.action.error?.count), [3, 0])
    }

    func testCurrentViewErrorCompletesWhenSessionIsNotSampled() throws {
        let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 0), dateProvider: DateProviderMock())
        monitor.startView(key: "ordinary")
        var completions = 0
        monitor.addError(error: ErrorMock("unsampled"), source: .custom, attributes: [:], completionHandler: { completions += 1 })
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(try XCTUnwrap(featureScope as? FeatureScopeMock).eventsWritten(ofType: RUMErrorEvent.self).isEmpty)
    }

    func testCurrentViewErrorCompletesWithoutSceneRecipient() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
        _ = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let eventCount = scope.eventsWritten.count
        var completions = 0
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: "missing") {
            monitor.addError(error: ErrorMock("no recipient"), source: .custom, attributes: [:], completionHandler: { completions += 1 })
        }
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(scope.eventsWritten.count, eventCount)
    }

    func testUnavailableErrorTargetsPreserveIndependentFallbacks() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let a = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let b = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        let unavailable = RUMCommandTarget.scene(RUMSceneIdentifier(rawValue: "closed"))
        var completions = 0
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: a, sceneIdentifier: sceneB.rawValue) {
            monitor.addError(error: ErrorMock("exact"), source: .custom, attributes: [:], explicitTarget: unavailable)
        }
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.addError(
                message: "scene",
                type: nil,
                stack: nil,
                source: .custom,
                attributes: [:],
                file: "Example/Error.swift",
                line: 42,
                explicitTarget: unavailable
            )
        }
        monitor.addError(error: ErrorMock("representative"), source: .custom, attributes: [:], completionHandler: { completions += 1 }, explicitTarget: unavailable)
        monitor.process(command: RUMStopViewCommand.mockWith(time: dateProvider.now, identity: ViewIdentifier("view-A"), target: .scene(sceneA)))
        monitor.addError(error: ErrorMock("ended"), source: .custom, attributes: [:], explicitTarget: .scene(sceneA))
        let errors = try XCTUnwrap(featureScope as? FeatureScopeMock).eventsWritten(ofType: RUMErrorEvent.self)
        XCTAssertEqual(errors.map(\.view.id), [a.viewID, a.viewID, b.viewID, b.viewID])
        XCTAssertEqual(errors[1].error.stack, "Error.swift:42")
        XCTAssertEqual(completions, 1)
    }

    func testExplicitErrorUsesCurrentOccurrenceAfterNavigationAndExpiration() throws {
        for delayed in [false, true] {
            let dateProvider = DateProviderMock()
            let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
            let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
            let oldA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
            monitor.process(command: RUMStartViewCommand.mockWith(
                time: dateProvider.now, identity: ViewIdentifier("next-A"), name: "Next A", target: .scene(sceneA)
            ))
            monitor.addAction(type: .custom, name: "representative B", attributes: [:], explicitTarget: .scene(sceneB))
            let nextA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
            monitor.addError(error: ErrorMock("next A"), source: .custom, attributes: [:], explicitTarget: .scene(sceneA))
            dateProvider.now = dateProvider.now.addingTimeInterval(4 * 60 * 60 + 1)
            if delayed {
                monitor.process(command: RUMHandleAppLifecycleEventCommand(time: dateProvider.now, event: .willEnterForeground))
            }
            var completions = 0
            monitor.addError(
                error: ErrorMock("restored A"),
                source: .custom,
                attributes: [:],
                completionHandler: { completions += 1 },
                explicitTarget: .scene(sceneA)
            )
            let errors = try XCTUnwrap(featureScope as? FeatureScopeMock).eventsWritten(ofType: RUMErrorEvent.self).suffix(2)
            XCTAssertEqual(errors.first?.view.id, nextA.viewID)
            XCTAssertNotEqual(nextA.viewID, oldA.viewID)
            XCTAssertEqual(errors.last?.view.name, "Next A")
            XCTAssertNotEqual(errors.last?.view.id, nextA.viewID)
            XCTAssertNotEqual(errors.last?.session.id, nextA.sessionID)
            XCTAssertEqual(completions, 1)
            XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewName, "View B")
        }
    }

    func testCurrentErrorTargetDoesNotReplaceCapturedResourceErrorOwner() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: dateProvider)
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        monitor.startAction(type: .tap, name: "A", attributes: [:], explicitTarget: .scene(sceneA))
        monitor.startAction(type: .tap, name: "B", attributes: [:], explicitTarget: .scene(sceneB))
        let owner = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let peer = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        startTargetedResource(in: monitor, form: .url, key: "original-A", target: .scene(sceneA))
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: peer, sceneIdentifier: sceneB.rawValue) {
            monitor.addError(error: ErrorMock("current B"), source: .custom, attributes: [:], explicitTarget: .scene(sceneB))
            monitor.stopResourceWithError(resourceKey: "original-A", message: "captured A")
        }
        monitor.stopAction(type: .tap, name: nil, attributes: [:], explicitTarget: .scene(sceneA))
        monitor.stopAction(type: .tap, name: nil, attributes: [:], explicitTarget: .scene(sceneB))
        let scope = try XCTUnwrap(featureScope as? FeatureScopeMock)
        let errors = scope.eventsWritten(ofType: RUMErrorEvent.self)
        XCTAssertEqual(errors.map(\.view.id), [peer.viewID, owner.viewID])
        XCTAssertEqual(errors.map(\.action?.id), [peer.userActionID, owner.userActionID].map { $0.map { RUMActionID.string(value: $0) } })
        let actions = scope.eventsWritten(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.map(\.action.error?.count), [1, 1])
        XCTAssertEqual(actions.map(\.action.resource?.count), [0, 0])
        XCTAssertTrue(scope.eventsWritten(ofType: RUMResourceEvent.self).isEmpty)
    }

    func testErrorCompletionCoversMapperDropsAndReentrantCalls() throws {
        for dropsError in [false, true] {
            let scope = FeatureScopeMock()
            let builder = RUMEventBuilder(eventsMapper: .mockWith(errorEventMapper: { dropsError ? nil : $0 }))
            let monitor = Monitor(
                dependencies: .mockWith(featureScope: scope, samplingRate: 100, eventBuilder: builder),
                dateProvider: DateProviderMock()
            )
            monitor.startView(key: "ordinary")
            var completions = 0
            monitor.addError(error: ErrorMock("outer"), source: .custom, attributes: [:]) {
                completions += 1
                monitor.addError(error: ErrorMock("nested"), source: .custom, attributes: [:]) { completions += 1 }
            }
            XCTAssertEqual(completions, 2)
            XCTAssertEqual(scope.eventsWritten(ofType: RUMErrorEvent.self).count, dropsError ? 0 : 2)
        }
    }

    func testDroppedErrorCompletesWhenMonitorIsReleasedBeforeDeferredProcessing() {
        let scope = FeatureScopeMock(deferEventWriteContext: true)
        var monitor: Monitor? = Monitor(dependencies: .mockWith(featureScope: scope, samplingRate: 100), dateProvider: DateProviderMock())
        var completions = 0
        monitor?.addError(error: ErrorMock("queued"), source: .custom, attributes: [:]) { completions += 1 }
        XCTAssertEqual(completions, 0)
        monitor = nil
        scope.flushDeferredEventWriteContexts()
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(scope.eventsWritten(ofType: RUMErrorEvent.self).isEmpty)
    }

    func testSuppressedCurrentViewErrorCompletesWithoutWriting() throws {
        let monitor = Monitor(dependencies: .mockWith(featureScope: featureScope, samplingRate: 100), dateProvider: DateProviderMock())
        var completions = 0
        var command = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(completionHandler: { completions += 1 })
        command.target = .none
        monitor.process(command: command)
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(try XCTUnwrap(featureScope as? FeatureScopeMock).eventsWritten(ofType: RUMErrorEvent.self).isEmpty)
    }

    func testGivenManualErrorsDuringSceneHandoff_theyUseExactOrSceneContext() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startAction(type: .tap, name: "Tap A", attributes: [:])
        }
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneB.rawValue) {
            monitor.startAction(type: .tap, name: "Tap B", attributes: [:])
        }
        let contextA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let contextB = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: contextA, sceneIdentifier: sceneB.rawValue) {
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
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.addError(error: ErrorMock("scene A error"), source: .source, attributes: [:])
        }
        var didComplete = false
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: contextA, sceneIdentifier: sceneB.rawValue) {
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

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: contextA, sceneIdentifier: sceneB.rawValue) {
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
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
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

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startView(key: "Home", name: "Home A", attributes: [:])
        }
        let firstA = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneB.rawValue) {
            monitor.startView(key: "Home", name: "Home B", attributes: [:])
        }
        let firstB = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        XCTAssertNotEqual(firstA.viewID, firstB.viewID)

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.stopView(key: "Home", attributes: [:])
        }
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID, firstB.viewID)

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
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

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: contextA, sceneIdentifier: sceneB.rawValue) {
            monitor.startView(key: "detail", name: "Detail A", attributes: [:])
        }

        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneA))?.viewName, "Detail A")
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID, contextB.viewID)
    }

    #if os(iOS)
    @MainActor
    func testGivenBackgroundControllerCalls_itAvoidsHierarchyReadsAndKeepsRepresentativeFallback() async throws {
        try await assertBackgroundControllerCalls(inSceneA: false)
    }

    @MainActor
    func testGivenBackgroundControllerCallsDuringHandoff_itAvoidsHierarchyReadsAndKeepsInferredScene() async throws {
        try await assertBackgroundControllerCalls(inSceneA: true)
    }

    @MainActor
    private func assertBackgroundControllerCalls(inSceneA: Bool) async throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)
        let peerScene = inSceneA ? sceneB : sceneA
        let peerID = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(peerScene))?.viewID)
        let controller = HierarchyReadSpy()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                XCTAssertFalse(Thread.isMainThread)
                let call = {
                    monitor.startView(viewController: controller, name: "Background Controller", attributes: [:])
                    monitor.stopView(viewController: controller, attributes: [:])
                }
                if inSceneA {
                    RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue, operation: call)
                } else {
                    call()
                }
                continuation.resume()
            }
        }

        XCTAssertEqual(controller.hierarchyReadCount, 0)
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(peerScene))?.viewID, peerID)
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(inSceneA ? sceneA : sceneB)))
        let views = try XCTUnwrap(featureScope as? FeatureScopeMock).eventsWritten(ofType: RUMViewEvent.self)
        let backgroundViews = views.filter { $0.view.name == "Background Controller" }
        XCTAssertEqual(Set(backgroundViews.map(\.view.id)).count, 1)
        XCTAssertEqual(backgroundViews.last?.view.isActive, false)
    }
    #endif

    #if os(iOS)
    func testGivenUnattachedViewController_whenStartedDuringSceneHandoff_itUsesThatScene() throws {
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: dateProvider
        )
        let (sceneA, sceneB) = startConcurrentSceneViews(in: monitor, dateProvider: dateProvider)

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
            monitor.startView(viewController: UIViewController(), name: "Controller A", attributes: [:])
        }
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneA))?.viewName, "Controller A")

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneB.rawValue) {
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

        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneA.rawValue) {
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

#if os(iOS)
private final class HierarchyReadSpy: UIViewController {
    private let readsLock = NSLock()
    private var reads = 0

    var hierarchyReadCount: Int {
        readsLock.lock()
        defer { readsLock.unlock() }
        return reads
    }

    override var viewIfLoaded: UIView? {
        readsLock.lock()
        reads += 1
        readsLock.unlock()
        return nil
    }
}
#endif
