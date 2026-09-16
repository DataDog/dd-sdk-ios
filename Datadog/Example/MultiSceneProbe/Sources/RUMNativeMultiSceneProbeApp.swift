/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import OSLog
import SwiftUI
import UIKit
import DatadogCore
import DatadogRUM
import DatadogTrace

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
        static let operationInstance = "probe.operation_instance"
        static let operationStep = "probe.operation_step"
    }

    static let serviceName = "ios-sdk-native-multi-scene-probe"
    static let resolution = ProbeScenarioRunner.resolve()
    static let runID = resolution.manifest.runID
    static let isRunnable = resolution.isValid

    private static let scenario = resolution.scenario
    private static let options = scenario?.runtimeOptions ?? ProbeRuntimeOptions()
    static let eventRecorder = ProbeEventRecorder(
        runID: runID,
        scenarioID: scenario?.identifier ?? "invalid",
        terminalSink: { result in
            logger.notice("semantic-result \(result, privacy: .public)")
        }
    )
    @MainActor static let sceneRegistry = ProbeSceneRegistry()
    static let usesObservableScenarioDriver = scenario.map(
        ProbeScenarioCatalog.usesObservableDriver
    ) ?? false
    static let usesSceneTargetedPresentationAuthority = scenario.map(
        ProbeScenarioCatalog.usesSceneTargetedPresentationAuthority
    ) ?? false
    static let usesSemanticNavigationSPI = scenario.map(
        ProbeScenarioCatalog.usesSemanticNavigationSPI
    ) ?? false
    static let usesSemanticNavigationHostSPI = scenario.map(
        ProbeScenarioCatalog.usesSemanticNavigationHostSPI
    ) ?? false
    static let usesExplicitSemanticNavigationHostSPI = scenario.map(
        ProbeScenarioCatalog.usesExplicitSemanticNavigationHostSPI
    ) ?? false
    static let usesExplicitSemanticNavigationPrecedenceSPI = scenario.map(
        ProbeScenarioCatalog.usesExplicitSemanticNavigationPrecedenceSPI
    ) ?? false
    static let usesCapabilitySemanticNavigationHostSPI = scenario.map(
        ProbeScenarioCatalog.usesCapabilitySemanticNavigationHostSPI
    ) ?? false
    static let usesObservedSemanticNavigationCapabilitySPI = scenario.map(
        ProbeScenarioCatalog.usesObservedSemanticNavigationCapabilitySPI
    ) ?? false
    static let usesSemanticNavigationHostLifetimeTestingSPI = scenario.map(
        ProbeScenarioCatalog.usesSemanticNavigationHostLifetimeTestingSPI
    ) ?? false
    static let usesSemanticNavigationHostFinalDetachSPI = scenario.map(
        ProbeScenarioCatalog.usesSemanticNavigationHostFinalDetachSPI
    ) ?? false
    static let replacesSemanticNavigationCapabilitySource = scenario.map(
        ProbeScenarioCatalog.replacesSemanticNavigationCapabilitySource
    ) ?? false
    static let usesAutomaticSemanticNavigationHostSPI = scenario.map(
        ProbeScenarioCatalog.usesAutomaticSemanticNavigationHostSPI
    ) ?? false
    static let usesEXP147RouterStreamAdapter = scenario.map(
        ProbeScenarioCatalog.usesEXP147RouterStreamAdapter
    ) ?? false
    static let usesEXP151ObservationRouterAdapter = scenario.map(
        ProbeScenarioCatalog.usesEXP151ObservationRouterAdapter
    ) ?? false
    static let usesEXP147NavigationFixture = scenario.map(
        ProbeScenarioCatalog.usesEXP147NavigationFixture
    ) ?? false
    static let usesExactSemanticNavigationHostSPI = scenario.map(
        ProbeScenarioCatalog.usesExactSemanticNavigationHostSPI
    ) ?? false
    static let usesSemanticNavigationValueLinks = scenario.map(
        ProbeScenarioCatalog.usesSemanticNavigationValueLinks
    ) ?? false
    @MainActor static let scenarioDriver: ProbeScenarioDriver? = {
        guard usesObservableScenarioDriver, let scenario else {
            return nil
        }
        return ProbeScenarioDriver(
            scenario: scenario,
            recorder: eventRecorder,
            sceneRegistry: sceneRegistry,
            stepTimeoutNanoseconds: usesSemanticNavigationValueLinks
                ? 180_000_000_000
                : options.exercisesSwiftUIButtonStructuredTask
                ? 180_000_000_000
                : options.exercisesUIKitScrollOwnership
                    ? 60_000_000_000
                    : 10_000_000_000
        )
    }()

    static let automaticallyNavigates = options.automaticallyNavigates
    static let initialSwiftUIPath = options.initialSwiftUIPath
    static let swiftUIRouterWritePolicy = options.swiftUIRouterWritePolicy
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
    static let exercisesUIKitScrollOwnership = options.exercisesUIKitScrollOwnership
    static let exercisesTraceOnlyURLSessionOwnership =
        options.exercisesTraceOnlyURLSessionOwnership
    static let exercisesSwiftUIButtonStructuredTask =
        options.exercisesSwiftUIButtonStructuredTask
    static let uiEventHandoffControlAccessibilityIdentifier =
        "probe.native.uikit-ui-event-handoff"
    static let uiKitScrollAccessibilityIdentifier = "probe.native.uikit-scroll"
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
    static let usesSiblingContainerAuthorityStress =
        options.swiftUIStress == .siblingContainerAuthority

    static func usesSemanticNavigationTracking(in logicalSceneID: String) -> Bool {
        guard usesNavigationOccurrenceSwiftUIViewTracking else {
            return false
        }
        return options.semanticNavigationSceneIDs?.contains(logicalSceneID) ?? true
    }

    static func usesManualSwiftUIViewTracking(
        in logicalSceneID: String,
        screen: String
    ) -> Bool {
        options.manualSwiftUIViewScreensByScene[logicalSceneID]?.contains(screen) == true
    }

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
                uiKitViewsPredicate: ProbeUIKitViewsPredicate(),
                uiKitActionsPredicate: exercisesUIEventContextHandoff
                    || exercisesUIKitScrollOwnership
                    ? ProbeUIKitActionsPredicate()
                    : nil,
                swiftUIViewsPredicate: usesAutomaticSwiftUIViewTracking
                    || usesNavigationOccurrenceSwiftUIViewTracking
                    ? ProbeSwiftUIViewsPredicate()
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

        if exercisesTraceOnlyURLSessionOwnership {
            Trace.enable(
                with: Trace.Configuration(
                    sampleRate: 100,
                    service: serviceName,
                    tags: [Attribute.runID: runID],
                    urlSessionTracking: .init(
                        firstPartyHostsTracing: .trace(
                            hosts: [ProbeTraceOnlyURLSessionContract.host],
                            sampleRate: 100,
                            traceControlInjection: .all
                        )
                    ),
                    bundleWithRumEnabled: true,
                    eventMapper: { event in
                        record(traceEvent: event)
                        return event
                    }
                )
            )
        }

        record(
            "configured service=\(serviceName) "
                + "scenario=\(scenario?.identifier ?? "invalid") "
                + "run_mode=\(resolution.manifest.runMode.rawValue) "
                + "swiftui_view_tracking=\(swiftUIViewTrackingMode) "
                + "swiftui_semantic_navigation_api=\(usesSemanticNavigationSPI) "
                + "swiftui_semantic_navigation_host=\(usesSemanticNavigationHostSPI) "
                + "swiftui_navigation_host_explicit=\(usesExplicitSemanticNavigationHostSPI) "
                + "swiftui_navigation_host_capability=\(usesCapabilitySemanticNavigationHostSPI) "
                + "swiftui_navigation_host_automatic=\(usesAutomaticSemanticNavigationHostSPI) "
                + "swiftui_navigation_host_router_stream="
                + "\(usesEXP147RouterStreamAdapter) "
                + "swiftui_navigation_host_current_destination="
                + "\(usesEXP151ObservationRouterAdapter) "
                + "swiftui_stress=\(options.swiftUIStress.rawValue) "
                + "initial_swiftui_path=\(initialSwiftUIPath.joined(separator: ",")) "
                + "swiftui_router_write_policy=\(swiftUIRouterWritePolicy.rawValue) "
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
                + "trace_only_urlsession=\(exercisesTraceOnlyURLSessionOwnership) "
                + "swiftui_button_structured_task=\(exercisesSwiftUIButtonStructuredTask) "
                + "semantic_navigation_scenes="
                + "\(options.semanticNavigationSceneIDs?.joined(separator: ",") ?? "all") "
                + "manual_swiftui_view_screens_by_scene="
                + "\(options.manualSwiftUIViewScreensByScene) "
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

    @MainActor
    static func waitForSwiftUIButtonStructuredTaskRelease(
        window: ProbeWindow,
        sceneSessionID: String,
        screen: String
    ) async -> Bool {
        await swiftUIButtonStructuredTaskGate.waitUntilReleased {
            eventRecorder.record(
                ProbeSignal(
                    kind: .assertion,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: window.label,
                        nativeSceneID: sceneSessionID,
                        screen: screen
                    ),
                    name: ProbeSwiftUIButtonStructuredTaskContract.startedAssertion,
                    result: .pass,
                    reason: "SwiftUI Button Task is suspended at its controlled gate"
                )
            )
            record(
                "SwiftUI Button structured Task waiting source=\(window.label) "
                    + "native=\(sceneSessionID) screen=\(screen)"
            )
        }
    }

    @MainActor
    static func releaseSwiftUIButtonStructuredTask(
        releasingScene: String
    ) -> ProbeStepExecutionResult {
        let result = swiftUIButtonStructuredTaskGate.release()
        if case .accepted = result {
            record("SwiftUI Button structured Task released scene=\(releasingScene)")
        }
        return result
    }

    static func recordSwiftUIButtonStructuredTaskCompletion(
        window: ProbeWindow,
        sceneSessionID: String,
        screen: String
    ) {
        eventRecorder.record(
            ProbeSignal(
                kind: .assertion,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: window.label,
                    nativeSceneID: sceneSessionID,
                    screen: screen
                ),
                name: ProbeSwiftUIButtonStructuredTaskContract.completedAssertion,
                result: .pass,
                reason: "SwiftUI Button Task emitted its post-suspension marker"
            )
        )
    }

    static func startTraceOnlyURLSessionRequest(
        window: ProbeWindow,
        sceneSessionID: String,
        screen: String,
        requestName: String
    ) -> ProbeStepExecutionResult {
        guard exercisesTraceOnlyURLSessionOwnership else {
            return .rejected(reason: "Trace-only URLSession tracking is disabled")
        }
        let sourceContext = ProbeSourceContext(
            logicalSceneID: window.label,
            nativeSceneID: sceneSessionID,
            screen: screen,
            phase: requestName,
            uptime: ProcessInfo.processInfo.systemUptime
        )
        let url = ProbeTraceOnlyURLSessionContract.requestURL(
            runID: runID,
            sourceScene: window.label,
            sourceScreen: screen,
            requestName: requestName
        )
        let result = traceOnlyURLSessionController.start(
            requestName: requestName,
            url: url,
            sourceContext: sourceContext
        )
        if case .accepted = result {
            record(
                "trace-only request scheduled source=\(window.label) "
                    + "native=\(sceneSessionID) screen=\(screen) "
                    + "request=\(requestName)"
            )
        }
        return result
    }

    static func completeTraceOnlyURLSessionRequest(
        requestName: String,
        releasingScene: String
    ) -> ProbeStepExecutionResult {
        guard exercisesTraceOnlyURLSessionOwnership else {
            return .rejected(reason: "Trace-only URLSession tracking is disabled")
        }
        let result = traceOnlyURLSessionController.complete(
            requestName: requestName
        )
        if case .accepted = result {
            record(
                "trace-only response released scene=\(releasingScene) "
                    + "request=\(requestName)"
            )
        }
        return result
    }

    static func joinTraceOnlyURLSessionRequest(
        window: ProbeWindow,
        sceneSessionID: String,
        screen: String,
        requestName: String
    ) -> ProbeStepExecutionResult {
        guard exercisesTraceOnlyURLSessionOwnership else {
            return .rejected(reason: "Trace-only URLSession tracking is disabled")
        }
        guard requestName == ProbeTraceOnlyURLSessionContract.sharedRequestName else {
            return .rejected(reason: "Trace-only request \(requestName) is not shared")
        }
        let result = traceOnlyURLSessionController.join(requestName: requestName)
        if case .accepted = result {
            let sourceContext = ProbeSourceContext(
                logicalSceneID: window.label,
                nativeSceneID: sceneSessionID,
                screen: screen,
                phase: requestName,
                uptime: ProcessInfo.processInfo.systemUptime
            )
            eventRecorder.record(
                ProbeSignal(
                    kind: .assertion,
                    sourceContext: sourceContext,
                    name: "trace-only-request-joined-\(requestName)",
                    result: .pass,
                    reason: "Joined the existing Trace-only request without starting another task"
                )
            )
            record(
                "trace-only request joined source=\(window.label) "
                    + "native=\(sceneSessionID) screen=\(screen) "
                    + "request=\(requestName)"
            )
        }
        return result
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

    private static func record(traceEvent event: SpanEvent) {
        guard let signal = ProbeRUMEventAdapter.trace(event, runID: runID) else {
            return
        }
        eventRecorder.record(signal)
        record(
            "payload type=trace session=\(signal.rumContext?.sessionID ?? "nil") "
                + "view=\(signal.rumContext?.viewID ?? "nil") "
                + "operation=\(event.operationName) request=\(signal.name ?? "nil")"
        )
    }

    private static let traceOnlyURLSessionController =
        ProbeTraceOnlyURLSessionController(
            didStart: { sourceContext in
                eventRecorder.record(
                    ProbeSignal(
                        kind: .assertion,
                        sourceContext: sourceContext,
                        name: "trace-only-request-started-\(sourceContext.phase ?? "unknown")",
                        result: .pass
                    )
                )
            },
            didComplete: { sourceContext, error in
                let result: ProbeSemanticResultState = error == nil ? .pass : .fail
                eventRecorder.record(
                    ProbeSignal(
                        kind: .assertion,
                        sourceContext: sourceContext,
                        name: "trace-only-request-completed-\(sourceContext.phase ?? "unknown")",
                        result: result,
                        reason: error.map {
                            "controlled Trace-only request failed with "
                                + String(reflecting: type(of: $0))
                        }
                    )
                )
            }
        )

    @MainActor private static let swiftUIButtonStructuredTaskGate =
        ProbeSwiftUIButtonStructuredTaskGate()

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

@MainActor
private final class ProbeSwiftUIButtonStructuredTaskGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var wasReleased = false

    func waitUntilReleased(onWaiting: () -> Void) async -> Bool {
        guard continuation == nil, !wasReleased else {
            return false
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onWaiting()
        }
        return true
    }

    func release() -> ProbeStepExecutionResult {
        guard !wasReleased, let continuation else {
            return .rejected(
                reason: "SwiftUI Button structured Task is not waiting"
            )
        }
        wasReleased = true
        self.continuation = nil
        continuation.resume()
        return .accepted
    }
}

private final class ProbeTraceOnlyURLSessionController: @unchecked Sendable {
    private struct InFlightRequest {
        let url: URL
        let session: URLSession
        let task: URLSessionDataTask
        let sourceContext: ProbeSourceContext
    }

    private let lock = NSLock()
    private var requests: [String: InFlightRequest] = [:]
    private let didStart: @Sendable (ProbeSourceContext) -> Void
    private let didComplete: @Sendable (ProbeSourceContext, Error?) -> Void

    init(
        didStart: @escaping @Sendable (ProbeSourceContext) -> Void,
        didComplete: @escaping @Sendable (ProbeSourceContext, Error?) -> Void
    ) {
        self.didStart = didStart
        self.didComplete = didComplete
    }

    func start(
        requestName: String,
        url: URL,
        sourceContext: ProbeSourceContext
    ) -> ProbeStepExecutionResult {
        lock.lock()
        defer { lock.unlock() }

        guard requests[requestName] == nil else {
            return .rejected(reason: "Trace-only request \(requestName) is already active")
        }
        guard ProbeTraceOnlyURLProtocol.prepare(
            url: url,
            sourceContext: sourceContext,
            didStart: didStart
        ) else {
            return .rejected(reason: "Trace-only protocol fixture is already prepared")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.protocolClasses = [ProbeTraceOnlyURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "GET"
        let task = session.dataTask(with: request) { [weak self, weak session] _, _, error in
            self?.finish(requestName: requestName, error: error)
            session?.finishTasksAndInvalidate()
        }
        requests[requestName] = InFlightRequest(
            url: url,
            session: session,
            task: task,
            sourceContext: sourceContext
        )
        task.resume()
        return .accepted
    }

    func complete(requestName: String) -> ProbeStepExecutionResult {
        lock.lock()
        let request = requests[requestName]
        lock.unlock()

        guard let request else {
            return .rejected(reason: "Trace-only request \(requestName) is not active")
        }
        guard ProbeTraceOnlyURLProtocol.complete(url: request.url) else {
            return .rejected(reason: "Trace-only request \(requestName) has not started loading")
        }
        return .accepted
    }

    func join(requestName: String) -> ProbeStepExecutionResult {
        lock.lock()
        defer { lock.unlock() }

        guard requests[requestName] != nil else {
            return .rejected(reason: "Trace-only request \(requestName) is not active")
        }
        return .accepted
    }

    private func finish(requestName: String, error: Error?) {
        lock.lock()
        let request = requests.removeValue(forKey: requestName)
        lock.unlock()
        guard let request else {
            return
        }
        didComplete(request.sourceContext, error)
    }
}

private final class ProbeTraceOnlyURLProtocol: URLProtocol {
    private final class Registration {
        let sourceContext: ProbeSourceContext
        let didStart: @Sendable (ProbeSourceContext) -> Void
        var loader: ProbeTraceOnlyURLProtocol?

        init(
            sourceContext: ProbeSourceContext,
            didStart: @escaping @Sendable (ProbeSourceContext) -> Void
        ) {
            self.sourceContext = sourceContext
            self.didStart = didStart
        }
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var registrations: [String: Registration] = [:]

        func prepare(
            key: String,
            sourceContext: ProbeSourceContext,
            didStart: @escaping @Sendable (ProbeSourceContext) -> Void
        ) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard registrations[key] == nil else {
                return false
            }
            registrations[key] = Registration(
                sourceContext: sourceContext,
                didStart: didStart
            )
            return true
        }

        func attach(
            loader: ProbeTraceOnlyURLProtocol,
            key: String
        ) -> Registration? {
            lock.lock()
            defer { lock.unlock() }
            guard
                let registration = registrations[key],
                registration.loader == nil
            else {
                return nil
            }
            registration.loader = loader
            return registration
        }

        func take(key: String) -> ProbeTraceOnlyURLProtocol? {
            lock.lock()
            defer { lock.unlock() }
            return registrations.removeValue(forKey: key)?.loader
        }

        func cancel(loader: ProbeTraceOnlyURLProtocol, key: String) {
            lock.lock()
            defer { lock.unlock() }
            guard registrations[key]?.loader === loader else {
                return
            }
            registrations.removeValue(forKey: key)
        }
    }

    private static let registry = Registry()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == ProbeTraceOnlyURLSessionContract.host
            && request.url?.path.hasPrefix("/trace-only/") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let url = request.url,
            let registration = Self.registry.attach(
                loader: self,
                key: url.absoluteString
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        registration.didStart(registration.sourceContext)
    }

    override func stopLoading() {
        guard let url = request.url else {
            return
        }
        Self.registry.cancel(loader: self, key: url.absoluteString)
    }

    fileprivate static func prepare(
        url: URL,
        sourceContext: ProbeSourceContext,
        didStart: @escaping @Sendable (ProbeSourceContext) -> Void
    ) -> Bool {
        registry.prepare(
            key: url.absoluteString,
            sourceContext: sourceContext,
            didStart: didStart
        )
    }

    fileprivate static func complete(url: URL) -> Bool {
        guard let loader = registry.take(key: url.absoluteString) else {
            return false
        }
        loader.finishSuccessfully(url: url)
        return true
    }

    private func finishSuccessfully(url: URL) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
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

private struct ProbeUIKitViewsPredicate: UIKitRUMViewsPredicate {
    private let defaultPredicate = DefaultUIKitRUMViewsPredicate()

    func rumView(for viewController: UIViewController) -> RUMView? {
        guard let child = viewController as? ProbeUIKitSplitChildViewController else {
            return defaultPredicate.rumView(for: viewController)
        }

        var view = RUMView(
            name: child.semanticRUMScreen,
            attributes: [
                ProbeRuntime.Attribute.viewScene: child.window.label,
                ProbeRuntime.Attribute.viewSceneSessionID: child.sceneSessionID,
                ProbeRuntime.Attribute.viewScreen: child.semanticRUMScreen
            ]
        )
        view.path = child.semanticRUMScreen
        return view
    }
}

private struct ProbeSwiftUIViewsPredicate: SwiftUIRUMViewsPredicate {
    private let defaultPredicate = DefaultSwiftUIRUMViewsPredicate()

    func rumView(for extractedViewName: String) -> RUMView? {
        guard extractedViewName != "ProbeControllerAncestryReader" else {
            ProbeRuntime.record(
                "filtered probe-only SwiftUI ancestry witness from automatic view tracking"
            )
            return nil
        }
        return defaultPredicate.rumView(for: extractedViewName)
    }
}

private struct ProbeUIKitActionsPredicate: UIKitRUMActionsPredicate {
    private let defaultPredicate = DefaultUIKitRUMActionsPredicate()

    func rumAction(targetView: UIView) -> RUMAction? {
        if let scrollView = targetView as? ProbeUIKitScrollTableView {
            let uptime = ProcessInfo.processInfo.systemUptime
            return RUMAction(
                name: "uikit-scroll-origin",
                attributes: [
                    ProbeRuntime.Attribute.runID: ProbeRuntime.runID,
                    ProbeRuntime.Attribute.host: "native-uikit",
                    ProbeRuntime.Attribute.sourceScene: scrollView.logicalSceneID,
                    ProbeRuntime.Attribute.sceneSessionID: scrollView.sceneSessionID,
                    ProbeRuntime.Attribute.screen: scrollView.screen,
                    ProbeRuntime.Attribute.phase: "uikit-scroll-origin",
                    ProbeRuntime.Attribute.uptime: uptime
                ]
            )
        }
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
