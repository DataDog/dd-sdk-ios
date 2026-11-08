/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import SwiftUI
import Combine
@testable import TestUtilities
@_spi(Internal)
@testable import DatadogInternal
@_spi(Internal)
@testable import DatadogCore
@testable import DatadogRUM

#if os(iOS) && canImport(SwiftUI)
extension SwiftUINavigationOwnershipTests {
    @MainActor
    func makeSemanticCore(directory: CoreDirectory? = nil) -> DatadogCore {
        DatadogCore(
            directory: directory ?? temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
    }

    @MainActor
    func makeSemanticFeature(
        in core: DatadogCore,
        rows: SemanticHostRows,
        enabled: Bool = true
    ) throws -> RUMFeature {
        let date = Date()
        core.contextProvider.write { context in
            context = .mockWith(
                sdkInitDate: date,
                launchInfo: .mockWith(
                    launchReason: .userLaunch,
                    processLaunchDate: date
                ),
                applicationStateHistory: .mockWith(
                    initialState: .active,
                    date: date
                )
            )
        }
        core.flush()
        var config = RUM.Configuration(
            applicationID: "semantic-host",
            trackAnonymousUser: false
        )
        config.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        config.featureFlags = [.multiSceneTracking: enabled]
        config.sessionSampleRate = 100
        config.vitalsUpdateFrequency = nil
        config.viewEventMapper = { rows.append($0); return $0 }
        config.actionEventMapper = { rows.append($0); return $0 }
        try RUM.enableOrThrow(
            with: config,
            in: core
        )
        core.flush()
        return try XCTUnwrap(core.get(feature: RUMFeature.self))
    }

    @MainActor
    func awaitSemanticBoundary(
        _ name: String,
        core: DatadogCore?,
        condition: () -> Bool
    ) async throws {
        if let core {
            try await awaitOrdinaryBoundary(
                name,
                core: core,
                condition: condition
            )
            return
        }
        let watchdog = Date().addingTimeInterval(20)
        while Date() < watchdog {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Missing semantic SwiftUI boundary: \(name)")
        throw OrdinarySwiftUIViewCaptureError.missingBoundary(name)
    }

    /// Reads the published legacy context on its SDK queue; Off has no scene snapshot store.
    @MainActor
    func awaitLegacySemanticView(
        _ boundary: String,
        core: DatadogCore?,
        feature: RUMFeature?,
        rows: SemanticHostRows,
        viewName: String
    ) async throws {
        let core = try XCTUnwrap(core)
        let feature = try XCTUnwrap(feature)
        guard !feature.monitor.isMultiSceneTrackingEnabled else {
            XCTFail("Legacy ownership check requires the Off path")
            throw OrdinarySwiftUIViewCaptureError.missingBoundary(boundary)
        }
        let watchdog = Date().addingTimeInterval(20)
        while Date() < watchdog {
            core.flush()
            let current: (id: String?, name: String?) = await withCheckedContinuation { continuation in
                feature.monitor.featureScope.context { context in
                    let rum = context.additionalContext(ofType: RUMCoreContext.self)
                    continuation.resume(returning: (rum?.viewID, rum?.viewName))
                }
            }
            if let id = current.id, current.name == viewName,
               rows.views.contains(where: { $0.view.id == id && $0.view.name == viewName && $0.view.isActive == true }) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Missing legacy SwiftUI ownership boundary: \(boundary)")
        throw OrdinarySwiftUIViewCaptureError.missingBoundary(boundary)
    }





}

@available(iOS 27.0, *)
@MainActor
private final class SemanticHostCapture {
    weak var state: RUMSemanticNavigationHostState?
    weak var admission: RUMSwiftUIViewCallbackAdmission?
    weak var observer: RUMSceneIdentifierReader.ObserverView?
    var configuredCore: ObjectIdentifier?
    var offeredSource: ObjectIdentifier?
    var configurationUpdates = 0
    var readerUpdates = 0

    func record(
        _ state: RUMSemanticNavigationHostState,
        admission: RUMSwiftUIViewCallbackAdmission?,
        observer: RUMSceneIdentifierReader.ObserverView?,
        core: ObjectIdentifier,
        offeredSource: ObjectIdentifier
    ) {
        self.state = state
        self.admission = admission
        self.configuredCore = core
        self.offeredSource = offeredSource
        if let observer {
            self.observer = observer
            readerUpdates += 1
        } else {
            configurationUpdates += 1
            if admission == nil { self.observer = nil }
        }
    }
}

@available(iOS 27.0, *)
@MainActor
private final class SemanticReaderHandshakeCapture {
    weak var observer: RUMSceneIdentifierReader.ObserverView?
    private weak var state: RUMSemanticNavigationHostState?
    private weak var source: RUMNavigationTransitions?
    private var callbacks: [[String: Any]] = []

    init(state: RUMSemanticNavigationHostState, source: RUMNavigationTransitions) {
        self.state = state
        self.source = source
    }

    func record(_ phase: String, proposedScene: String) {
        callbacks.append([
            "ordinal": callbacks.count, "phase": phase, "proposed_scene": proposedScene,
            "observer_identity": observer.map { String(describing: ObjectIdentifier($0)) } ?? "",
            "actual_window": observer?.window.map { String(describing: ObjectIdentifier($0)) } ?? "",
            "actual_scene": observer?.currentSceneIdentifier?.rawValue ?? "",
            "selected_source": state?.selectedTransitions.map { String(describing: ObjectIdentifier($0)) } ?? "",
            "active_occurrence": state?.currentIdentity ?? "", "source_observers": source?.observationCount ?? -1
        ])
    }

    func makeObserver(
        state: RUMSemanticNavigationHostState,
        admission: RUMSwiftUIViewCallbackAdmission
    ) -> RUMSceneIdentifierReader.ObserverView {
        RUMSceneIdentifierReader.ObserverView(
            admission: admission,
            onChange: { [weak state, weak admission, self] attachment in
                guard let state, let admission else {
                    return
                }
                let proposed: String
                if case .attached(let scene?) = attachment {
                    proposed = scene.rawValue
                } else {
                    proposed = ""
                }
                record("change-before", proposedScene: proposed)
                state.reconcile(attachment: attachment, admission: admission)
                record("change-after", proposedScene: proposed)
            },
            onMount: { [weak state, weak admission, self] scene in
                guard let state, let admission else {
                    return
                }
                record("mount-before", proposedScene: scene.rawValue)
                state.readerDidMount(in: scene, admission: admission)
                record("mount-after", proposedScene: scene.rawValue)
            },
            applicationSupportsMultipleScenes: true
        )
    }

    func retain(in test: XCTestCase, fixture: SemanticHostWindow) {
        let payload: [String: Any] = [
            "schema_version": 1, "family": "semantic-navigation-reader-handshake",
            "scene_identifier": fixture.identifier.rawValue,
            "owned_window": String(describing: ObjectIdentifier(fixture.window)),
            "callbacks": callbacks,
            "scope": "Reader/host first-attachment discriminator; no rendered SwiftUI or release-gate credit"
        ]
        do {
            let attachment = XCTAttachment(
                data: try JSONSerialization.data(withJSONObject: payload),
                uniformTypeIdentifier: "public.json"
            )
            attachment.name = "semantic-navigation-reader-handshake"
            attachment.lifetime = .keepAlways
            test.add(attachment)
        } catch {
            XCTFail("Could not retain reader mount observations")
        }
    }
}

@available(iOS 27.0, *)
@MainActor
private final class SemanticHostDriver: ObservableObject {
    @Published var core: DatadogCoreProtocol
    @Published var transitions: RUMNavigationTransitions
    @Published var visible = true
    let child = OrdinarySwiftUIViewDriver()

    init(core: DatadogCoreProtocol,
         transitions: RUMNavigationTransitions) {
        self.core = core
        self.transitions = transitions
    }
}

@available(iOS 27.0, *)
@MainActor
private struct SemanticHostRoot: View {
    @ObservedObject var driver: SemanticHostDriver
    let capture: SemanticHostCapture
    var trackLegacyContent = false

    var body: some View {
        let source = driver.transitions
        let core = driver.core
        let coreIdentity = ObjectIdentifier(core)
        let sourceIdentity = ObjectIdentifier(source)
        return Group {
            if driver.visible {
                RUMNavigationHost(
                    transitions: source,
                    in: core,
                    testingOnHostUpdate: { state, admission, observer in
                        capture.record(
                            state,
                            admission: admission,
                            observer: observer,
                            core: coreIdentity,
                            offeredSource: sourceIdentity
                        )
                    }
                ) {
                    if trackLegacyContent {
                        OrdinarySwiftUIViewChild(driver: driver.child)
                            .trackRUMView(
                                name: "Legacy Content",
                                in: core
                            )
                    } else {
                        OrdinarySwiftUIViewChild(driver: driver.child)
                    }
                }
            }
        }
    }
}

final class SemanticHostRows: @unchecked Sendable {
    private let lock = NSLock()
    private var viewValues: [RUMViewEvent] = []
    private var actionValues: [RUMActionEvent] = []
    func append(_ value: RUMViewEvent) { lock.lock(); defer { lock.unlock() }; viewValues.append(value) }
    func append(_ value: RUMActionEvent) { lock.lock(); defer { lock.unlock() }; actionValues.append(value) }
    var views: [RUMViewEvent] { lock.lock(); defer { lock.unlock() }; return viewValues }
    var actions: [RUMActionEvent] { lock.lock(); defer { lock.unlock() }; return actionValues }
}

@MainActor
final class SemanticHostWindow {
    let scene: UIWindowScene
    let window: UIWindow
    let identifier: RUMSceneIdentifier
    private let originalRoot: UIViewController
    private let originalHidden: Bool
    private let originalKey: UIWindow?

    init() throws {
        let expected = try XCTUnwrap(NSClassFromString("RUMSceneTestHost.RUMTestSceneDelegate"))
        let owned = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
            $0.activationState != .unattached && $0.delegate.map {
                ObjectIdentifier(type(of: $0)) == ObjectIdentifier(expected)
            } == true
        }
        XCTAssertEqual(owned.count, 1)
        scene = try XCTUnwrap(owned.first)
        let delegate = try XCTUnwrap(scene.delegate as? UIWindowSceneDelegate)
        window = try XCTUnwrap(delegate.window ?? nil)
        originalRoot = try XCTUnwrap(window.rootViewController)
        originalHidden = window.isHidden
        originalKey = scene.windows.first(where: \.isKeyWindow)
        identifier = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        XCTAssertTrue(window.windowScene === scene && scene.windows.contains { $0 === window })
        XCTAssertTrue(window.bounds.width.isFinite && window.bounds.height.isFinite
                        && window.bounds.width > 0 && window.bounds.height > 0)
    }

    func install<Content: View>(_ content: Content) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content)
        let container = UIViewController()
        window.rootViewController = container
        container.addChild(host)
        host.view.frame = container.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        window.makeKeyAndVisible()
        XCTAssertTrue(window.rootViewController === container && window.windowScene === scene)
        XCTAssertTrue(host.parent === container && host.view.superview === container.view)
        return host
    }

    func restore() {
        window.rootViewController = originalRoot
        window.isHidden = originalHidden
        originalKey?.makeKey()
    }
}
#endif
#if os(iOS) && canImport(SwiftUI)
extension SwiftUINavigationOwnershipTests {
    @available(iOS 27.0, *)
    @MainActor
    private func retainSemanticHostEvidence(
        name: String,
        phase: String,
        completed: Bool,
        fixture: SemanticHostWindow,
        rows: [String: SemanticHostRows],
        driver: SemanticHostDriver,
        capture: SemanticHostCapture,
        sources: [String: RUMNavigationTransitions],
        contexts: [String: RUMCoreContext?],
        facts: [String: Any]
    ) {
        do {
            let eventRows = try rows.mapValues { values -> [String: Any] in
                [
                    "views": try values.views.map {
                        try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
                    },
                    "actions": try values.actions.map {
                        try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
                    }
                ]
            }
            let contextRows = contexts.mapValues { value -> [String: String] in
                value.map {
                    [
                        "session_id": $0.sessionID, "view_id": $0.viewID ?? "",
                        "name": $0.viewName ?? "", "path": $0.viewPath ?? ""
                    ]
                } ?? [:]
            }
            let windows: [[String: Any]] = fixture.scene.windows.map { window in
                [
                    "identity": String(describing: ObjectIdentifier(window)),
                    "fixture_delegate_window": window === fixture.window,
                    "key": window.isKeyWindow, "hidden": window.isHidden,
                    "width": Double(window.bounds.width), "height": Double(window.bounds.height),
                    "scene_matches": window.windowScene === fixture.scene
                ]
            }
            let payload: [String: Any] = [
                "schema_version": 1, "family": "private-semantic-navigation-host",
                "case": name, "attempted_phase": phase, "completed_schedule": completed,
                "scene_identifier": fixture.identifier.rawValue,
                "scene_activation": fixture.scene.activationState.rawValue,
                "application_state": UIApplication.shared.applicationState.rawValue,
                "window_inventory": windows,
                "root_identity": fixture.window.rootViewController.map {
                    String(describing: ObjectIdentifier($0))
                } ?? "",
                "customer_states": driver.child.states,
                "customer_disappearances": driver.child.disappearances,
                "source_observer_counts": sources.mapValues { $0.observationCount },
                "configuration_receipts": capture.configurationUpdates,
                "reader_receipts": capture.readerUpdates,
                "admission_valid": capture.admission?.isValid == true,
                "reader_scene": capture.observer?.currentSceneIdentifier?.rawValue ?? "",
                "contexts": contextRows, "event_rows": eventRows, "facts": facts,
                "scope": "Source/component control; no actual OS disconnect, automatic-input or release-gate credit"
            ]
            let attachment = XCTAttachment(
                data: try JSONSerialization.data(withJSONObject: payload),
                uniformTypeIdentifier: "public.json"
            )
            attachment.name = "semantic-navigation-host-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Could not retain semantic navigation host observations")
        }
    }
}
#endif
