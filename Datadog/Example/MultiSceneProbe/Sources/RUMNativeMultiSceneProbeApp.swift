/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import OSLog
import SwiftUI
import DatadogCore
import DatadogRUM

@main
struct RUMNativeMultiSceneProbeApp: App {
    init() {
        ProbeRuntime.configureDatadog()
    }

    var body: some Scene {
        WindowGroup(id: ProbeWindow.windowGroupID, for: ProbeWindow.self) { $window in
            if ProbeRuntime.isRunnable {
                ProbeWindowRoot(window: window)
            } else {
                ProbeConfigurationFailureView(
                    errors: ProbeRuntime.resolution.manifest.validationErrors
                )
            }
        } defaultValue: {
            ProbeWindow(
                runID: ProbeRuntime.runID,
                label: "scene-A",
                opensPeer: true
            )
        }
    }
}

enum ProbeRuntime {
    enum UIKitSplitInteractivePopOutcome: String {
        case cancel
        case finish
    }

    enum Attribute {
        static let runID = "probe.run_id"
        static let host = "probe.host"
        static let sourceScene = "probe.source_scene"
        static let sceneSessionID = "probe.scene_session_id"
        static let screen = "probe.screen"
        static let phase = "probe.phase"
        static let uptime = "probe.uptime"
        static let readerControlGeneration = "probe.reader_control_generation"
        static let viewScene = "probe.view.scene"
        static let viewSceneSessionID = "probe.view.scene_session_id"
        static let viewScreen = "probe.view.screen"
    }

    static let serviceName = "ios-sdk-native-multi-scene-probe"
    static let resolution = ProbeScenarioRunner.resolve()
    static let runID = resolution.manifest.runID
    static let isRunnable = resolution.isValid

    private static let scenario = resolution.scenario
    private static let options = scenario?.runtimeOptions ?? ProbeRuntimeOptions()
    static let eventRecorder = ProbeEventRecorder(
        runID: runID,
        scenarioID: scenario?.identifier ?? "invalid"
    )
    @MainActor static let sceneRegistry = ProbeSceneRegistry()
    static let usesObservableScenarioDriver = scenario.map {
        [
            "swiftui.stack.return",
            "swiftui.stack.abort",
            "swiftui.stack.same-type-replacement",
            "swiftui.stack.different-type-replacement",
            "swiftui.split.automatic-baseline",
            "swiftui.split.same-type-selection",
            "swiftui.split.retained-return"
        ].contains($0.identifier)
    } ?? false
    @MainActor static let scenarioDriver: ProbeScenarioDriver? = {
        guard usesObservableScenarioDriver, let scenario else {
            return nil
        }
        return ProbeScenarioDriver(
            scenario: scenario,
            recorder: eventRecorder,
            sceneRegistry: sceneRegistry
        )
    }()

    static let automaticallyNavigates = options.automaticallyNavigates
    static let automaticallyOpensSecondWindow = options.automaticallyOpensSecondWindow
    static let automaticallyClosesSceneB = options.automaticallyClosesSceneB
    static let automaticallyAbortsDetail = options.automaticallyAbortsDetail
    static let automaticallyReplacesDetail = options.automaticallyReplacesDetail
    static let automaticallyReplacesDetailInstance = options.automaticallyReplacesDetailInstance
    static let forcesNavigationRouteIdentity = options.forcesNavigationRouteIdentity
    static let syntheticReaderDisconnectTarget = options.syntheticReaderDisconnectTarget
    static let usesSplitSelectionLayout = scenario?.layout == .splitSelection
    static let usesUIKitSplitLayout = scenario?.layout == .uikitSplit
    static let usesUIKitSplitSubclass = scenario?.layout == .uikitSplitSubclass
    static let usesUIKitSplitNavigationLayout = scenario?.layout == .uikitSplitNavigation
    static let automaticallyPopsUIKitSplitNavigation =
        options.automaticallyPopsUIKitSplitNavigation
    static let uiKitSplitInteractivePopOutcome = options.uiKitSplitInteractivePopOutcome
        .flatMap { UIKitSplitInteractivePopOutcome(rawValue: $0.rawValue) }
    static let startsSplitWithoutSelection = options.startsSplitWithoutSelection
    static let automaticallyAdvancesSplitSelection =
        options.automaticallyAdvancesSplitSelection
    static let automaticallyReturnsSplitToDetail = options.automaticallyReturnsSplitToDetail
    static let exercisesUIEventContextHandoff = options.exercisesUIEventContextHandoff
    static let uiEventHandoffControlAccessibilityIdentifier =
        "probe.native.uikit-ui-event-handoff"
    static let usesAnySplitLayout =
        usesSplitSelectionLayout
        || usesUIKitSplitLayout
        || usesUIKitSplitSubclass
        || usesUIKitSplitNavigationLayout
    static let swiftUIViewTrackingMode = scenario?.trackingMode.rawValue ?? "invalid"
    static let usesAutomaticSwiftUIViewTracking = swiftUIViewTrackingMode == "automatic"
    static let usesNavigationPathSwiftUIViewTracking = swiftUIViewTrackingMode == "navigation-path"
    static let usesNavigationOccurrenceSwiftUIViewTracking =
        swiftUIViewTrackingMode == "navigation-occurrence"
    static let usesTabPreloadStress = options.swiftUIStress == .tabPreload

    private static let logger = Logger(
        subsystem: "com.datadoghq.rum-native-multi-scene-probe",
        category: "probe"
    )

    static func configureDatadog() {
        ProbeScenarioRunner.emitManifest(resolution.manifest)

        guard isRunnable else {
            record(
                "configuration rejected errors="
                    + resolution.manifest.validationErrors.joined(separator: " | ")
            )
            return
        }

        guard
            let clientToken = configuredValue(for: "DatadogClientToken"),
            let applicationID = configuredValue(for: "RUMApplicationID")
        else {
            record("configuration skipped reason=missing-credentials")
            return
        }

        Datadog.initialize(
            with: Datadog.Configuration(
                clientToken: clientToken,
                env: "multi-scene-probe",
                service: serviceName,
                batchSize: .small,
                uploadFrequency: .frequent
            ),
            trackingConsent: .granted
        )
        Datadog.verbosityLevel = .debug

        RUM.enable(
            with: RUM.Configuration(
                applicationID: applicationID,
                uiKitViewsPredicate: DefaultUIKitRUMViewsPredicate(),
                uiKitActionsPredicate: exercisesUIEventContextHandoff
                    ? ProbeUIKitActionsPredicate()
                    : nil,
                swiftUIViewsPredicate: usesAutomaticSwiftUIViewTracking
                    ? DefaultSwiftUIRUMViewsPredicate()
                    : nil,
                swiftUIActionsPredicate: DefaultSwiftUIRUMActionsPredicate(
                    isLegacyDetectionEnabled: false
                ),
                trackBackgroundEvents: true,
                viewEventMapper: { event in
                    record(viewEvent: event)
                    return event
                },
                resourceEventMapper: { event in
                    record(resourceEvent: event)
                    return event
                },
                actionEventMapper: { event in
                    record(actionEvent: event)
                    return event
                },
                errorEventMapper: { event in
                    record(errorEvent: event)
                    return event
                },
                onSessionStart: { sessionID, isDiscarded in
                    eventRecorder.record(
                        ProbeRUMEventAdapter.sessionStarted(
                            sessionID: sessionID,
                            isDiscarded: isDiscarded
                        )
                    )
                    record("session id=\(sessionID) discarded=\(isDiscarded)")
                },
                telemetrySampleRate: 100
            )
        )
        RUMMonitor.shared().debug = true
        RUMMonitor.shared().addAttribute(forKey: Attribute.runID, value: runID)
        RUMMonitor.shared().addAttribute(forKey: Attribute.host, value: "native-swiftui")

        record(
            "configured service=\(serviceName) "
                + "scenario=\(scenario?.identifier ?? "invalid") "
                + "run_mode=\(resolution.manifest.runMode.rawValue) "
                + "swiftui_view_tracking=\(swiftUIViewTrackingMode) "
                + "swiftui_stress=\(usesTabPreloadStress ? "tab-preload" : "none") "
                + "automatic_detail=\(automaticallyNavigates) "
                + "automatic_second_window=\(automaticallyOpensSecondWindow) "
                + "automatic_close_scene_b=\(automaticallyClosesSceneB) "
                + "automatic_abort_detail=\(automaticallyAbortsDetail) "
                + "automatic_replace_detail=\(automaticallyReplacesDetail) "
                + "automatic_replace_detail_instance=\(automaticallyReplacesDetailInstance) "
                + "force_route_identity=\(forcesNavigationRouteIdentity) "
                + "swiftui_layout=\(layoutDescription) "
                + "uikit_split_automatic_pop=\(automaticallyPopsUIKitSplitNavigation) "
                + "uikit_split_interactive_pop="
                + "\(uiKitSplitInteractivePopOutcome?.rawValue ?? "none") "
                + "split_initial_selection=\(startsSplitWithoutSelection ? "none" : "detail-1") "
                + "split_automatic_sequence=\(automaticallyAdvancesSplitSelection) "
                + "split_return_to_detail=\(automaticallyReturnsSplitToDetail) "
                + "ui_event_handoff=\(exercisesUIEventContextHandoff) "
                + "synthetic_reader_disconnect_target="
                + "\(syntheticReaderDisconnectTarget ?? "none")"
        )
    }

    private static var layoutDescription: String {
        scenario?.layout.rawValue ?? "invalid"
    }

    static func emitLifecycleMarker(
        window: ProbeWindow,
        sceneSessionID: String,
        screen: String,
        phase: String
    ) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let marker = "\(window.label).\(screen).\(phase)"
        let attributes: [String: Encodable] = [
            Attribute.runID: runID,
            Attribute.host: "native-swiftui",
            Attribute.sourceScene: window.label,
            Attribute.sceneSessionID: sceneSessionID,
            Attribute.screen: screen,
            Attribute.phase: phase,
            Attribute.uptime: uptime
        ]

        record(
            "lifecycle source=\(window.label) native=\(sceneSessionID) "
                + "screen=\(screen) phase=\(phase) uptime=\(uptime)"
        )
        RUMMonitor.shared().addAction(
            type: .custom,
            name: "probe-lifecycle-\(marker)",
            attributes: attributes
        )

        let resourceKey = "probe-resource-\(marker)-\(UUID().uuidString.lowercased())"
        let path = marker.replacingOccurrences(of: ".", with: "/")
        let url = URL(string: "https://multi-scene-probe.invalid/native/\(path)")!
        RUMMonitor.shared().startResource(
            resourceKey: resourceKey,
            url: url,
            attributes: attributes
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            RUMMonitor.shared().stopResource(
                resourceKey: resourceKey,
                statusCode: 200,
                kind: .other,
                size: 1,
                attributes: attributes
            )
        }
    }

    static func record(_ message: String) {
        let line = "run=\(runID) \(message)"
        print("🔬 [RUM Native Multi-Scene] \(line)")
        logger.notice("\(line, privacy: .public)")
    }

    @MainActor
    static func recordDestination(
        window: ProbeWindow,
        sceneSessionID: String,
        screen: String,
        isCommitted: Bool,
        occurrence: Int? = nil
    ) {
        if let handle = sceneRegistry.handle(logicalSceneID: window.label),
           handle.nativeSceneID == sceneSessionID {
            _ = sceneRegistry.updateRoute([screen], for: handle)
        }
        eventRecorder.record(
            ProbeSignal(
                kind: isCommitted
                    ? .destinationMaterialized
                    : .destinationAppearanceObserved,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID == "unresolved"
                        ? nil
                        : sceneSessionID,
                    screen: screen,
                    occurrence: occurrence
                )
            )
        )
    }

    @MainActor
    static func recordSceneSnapshot(
        _ snapshot: ProbeSceneSnapshot,
        kind: ProbeSignalKind
    ) {
        eventRecorder.record(
            ProbeSignal(
                kind: kind,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: snapshot.logicalSceneID,
                    nativeSceneID: snapshot.nativeSceneID,
                    screen: snapshot.currentRoute.last
                ),
                scenePhase: snapshot.readiness.rawValue,
                activationState: snapshot.presentation.activationState.rawValue,
                sceneDisconnectGeneration: snapshot.disconnectGeneration,
                geometry: snapshot.presentation.geometry,
                horizontalSizeClass: snapshot.presentation.horizontalSizeClass,
                verticalSizeClass: snapshot.presentation.verticalSizeClass,
                navigationPath: snapshot.currentRoute
            )
        )
    }

    private static func record(viewEvent event: RUMViewEvent) {
        eventRecorder.record(ProbeRUMEventAdapter.viewSnapshot(event))
        record(
            "payload type=view session=\(event.session.id) view=\(event.view.id) "
                + "name=\(event.view.name ?? "nil") "
                + "active=\(String(describing: event.view.isActive))"
        )
    }

    private static func record(actionEvent event: RUMActionEvent) {
        eventRecorder.record(ProbeRUMEventAdapter.action(event))
        record(
            "payload type=action session=\(event.session.id) view=\(event.view.id) "
                + "action=\(event.action.id) name=\(event.view.name ?? "nil") "
                + "target=\(event.action.target?.name ?? "nil")"
        )
    }

    private static func record(resourceEvent event: RUMResourceEvent) {
        eventRecorder.record(ProbeRUMEventAdapter.resource(event))
        let actionID: String
        switch event.action?.id {
        case .string(let value):
            actionID = value
        case .stringsArray(let values):
            actionID = values.joined(separator: ",")
        case nil:
            actionID = "nil"
        }
        record(
            "payload type=resource session=\(event.session.id) view=\(event.view.id) "
                + "action=\(actionID) resource=\(event.resource.id) "
                + "name=\(event.view.name ?? "nil") url=\(event.resource.url)"
        )
    }

    private static func record(errorEvent event: RUMErrorEvent) {
        eventRecorder.record(ProbeRUMEventAdapter.error(event))
        record(
            "payload type=error session=\(event.session.id) view=\(event.view.id) "
                + "error=\(event.error.id ?? "nil") name=\(event.view.name ?? "nil") "
                + "type=\(event.error.type ?? "nil") crash=\(event.error.isCrash ?? false)"
        )
    }

    private static func configuredValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            !trimmed.hasPrefix("//"),
            !trimmed.contains("$(")
        else {
            return nil
        }
        return trimmed
    }
}

private struct ProbeConfigurationFailureView: View {
    let errors: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Probe configuration rejected")
                    .font(.title2.bold())
                ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                    Text(error)
                        .font(.body.monospaced())
                }
            }
            .padding()
        }
        .accessibilityIdentifier("probe.configuration-rejected")
    }
}

private struct ProbeUIKitActionsPredicate: UIKitRUMActionsPredicate {
    private let defaultPredicate = DefaultUIKitRUMActionsPredicate()

    func rumAction(targetView: UIView) -> RUMAction? {
        if targetView.accessibilityIdentifier?.hasPrefix(
            ProbeRuntime.uiEventHandoffControlAccessibilityIdentifier
        ) == true {
            ProbeRuntime.record(
                "uikit automatic action filtered target="
                    + "\(targetView.accessibilityIdentifier ?? "unresolved")"
            )
            return nil
        }
        return defaultPredicate.rumAction(targetView: targetView)
    }
}
