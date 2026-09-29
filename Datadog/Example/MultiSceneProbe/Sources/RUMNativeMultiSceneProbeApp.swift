/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CryptoKit
import OSLog
import SwiftUI
import UIKit
import DatadogCore
import DatadogRUM
import DatadogTrace

@main
struct RUMNativeMultiSceneProbeApp: App {
    private let installedCodeVerified: Bool

    init() {
        do {
            try InstalledCodeReceipt.writeIfRequested(runID: ProbeRuntime.runID)
            installedCodeVerified = true
            ProbeRuntime.configureDatadog()
            ProbeRuntime.installPhysicalDisconnectWitnessIfRequested()
        } catch {
            installedCodeVerified = false
            print("INVALID: installed code identity could not be recorded")
        }
    }

    var body: some Scene {
        WindowGroup(id: ProbeWindow.windowGroupID, for: ProbeWindow.self) { $window in
            if !installedCodeVerified {
                Text("Invalid installed code identity")
            } else if ProbeRuntime.isRunnable {
                if ProbeFatalContract.isRecovery(ProbeRuntime.resolution.scenario?.identifier ?? "") {
                    Text("Crash report recovery").task { await ProbeFatalAcceptance.recover() }
                } else {
                    ProbeWindowRoot(window: window)
                }
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
        sink: ProbeArtifactCapture.record,
        terminalSink: { result in
            logger.notice("semantic-result \(result, privacy: .public)")
        }
    )
    @MainActor static let sceneRegistry = ProbeSceneRegistry()
    static let usesAdaptiveSplitAcceptance = [
        "swiftui.split.adaptive-accepted-state", "swiftui.split.adaptive-resize"
    ].contains(scenario?.identifier ?? "")
    static let usesAdaptiveSplitResizeAcceptance =
        scenario?.identifier == "swiftui.split.adaptive-resize"
    static let usesPhysicalAdaptiveSplitResizeAcceptance = usesAdaptiveSplitResizeAcceptance
        && ProcessInfo.processInfo.environment["DD_PROBE_PHYSICAL_ADAPTIVE_RESIZE"] == "1"
    static let usesObservableScenarioDriver = scenario.map(
        ProbeScenarioCatalog.usesObservableDriver
    ) ?? false
    static let usesSceneTargetedPresentationAuthority = scenario.map(
        ProbeScenarioCatalog.usesSceneTargetedPresentationAuthority
    ) ?? false
    static let usesExplicitOperationViewTargetSPI = scenario.map(
        ProbeScenarioCatalog.usesExplicitOperationViewTargetSPI
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
    static let usesEXP152NativeDismissCallbacks = scenario.map(
        ProbeScenarioCatalog.usesEXP152NativeDismissCallbacks
    ) ?? false
    static let usesEXP153ThirdPartyCallbackAdapter = scenario.map(
        ProbeScenarioCatalog.usesEXP153ThirdPartyCallbackAdapter
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
    static let physicalOperationCaptureRequested =
        ProcessInfo.processInfo.environment["DD_PROBE_PHYSICAL_OPERATION_CAPTURE"] == "1"
    @MainActor static let physicalOperationInput: ProbePhysicalOperationInput? =
        physicalOperationCaptureRequested && scenario?.identifier == ProbePhysicalOperationProfile.scenarioID
        ? .init(registry: sceneRegistry) : nil

    @MainActor static let scenarioDriver: ProbeScenarioDriver? = {
        guard usesObservableScenarioDriver, let scenario else {
            return nil
        }
        let physicalAdmission: ProbePhysicalTopologyAdmission?
        if scenario.identifier == ProbePhysicalTopologyAdmission.scenarioID,
           ProcessInfo.processInfo.environment["DD_PROBE_PHYSICAL_TOPOLOGY"] == "1",
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            physicalAdmission = .init(runID: runID, registry: sceneRegistry,
                                      recorder: eventRecorder, directory: documents)
        } else {
            physicalAdmission = nil
        }
        let stepAdmission: ((Int, ProbeStep, Bool) async -> String?)?
        if scenario.identifier == ProbePhysicalOperationSetupProfile.scenarioID {
            // A catalog selection alone never admits setup markers or SDK work.
            stepAdmission = { index, _, _ in
                index >= ProbePhysicalOperationSetupProfile.setupBoundary
                    ? "Operation setup and current-owner binding are not armed" : nil
            }
        } else if physicalOperationCaptureRequested {
            // Capture preparation cannot dispatch Operations without the reviewed host barrier.
            stepAdmission = { index, _, _ in
                guard scenario.identifier == ProbePhysicalOperationProfile.scenarioID else {
                    return "Operation capture requested for a different scenario"
                }
                return index >= ProbePhysicalOperationProfile.criticalInterval.lowerBound
                    ? "Operation host transport is not armed" : nil
            }
        } else {
            stepAdmission = physicalAdmission.map { admission in
                { index, step, after in await admission.check(index: index, step: step, after: after) }
            }
        }
        return ProbeScenarioDriver(
            scenario: scenario,
            recorder: eventRecorder,
            sceneRegistry: sceneRegistry,
            stepTimeoutNanoseconds: ProbeFatalContract.contains(scenario.identifier)
                || ProbeVitalsContract.contains(scenario.identifier)
                || scenario.identifier == ProbeProcessContract.scenarioID
                ? 60_000_000_000
                : usesSemanticNavigationValueLinks
                ? 180_000_000_000
                : options.exercisesSwiftUIButtonStructuredTask
                ? 180_000_000_000
                : options.exercisesUIKitScrollOwnership
                    ? 60_000_000_000
                    : 10_000_000_000,
            stepAdmission: stepAdmission
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

    static func usesSemanticNavigationContainer(in logicalSceneID: String) -> Bool {
        scenario.map {
            ProbeScenarioCatalog.usesSemanticNavigationContainer($0, in: logicalSceneID)
        } ?? false
    }

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

    @MainActor private static var physicalDisconnectObserver: NSObjectProtocol?

    /// Observe actual OS delivery independently of the window view being removed.
    @MainActor
    static func installPhysicalDisconnectWitnessIfRequested() {
        guard isRunnable,
              scenario?.identifier == "windows.activation-sequence",
              ProcessInfo.processInfo.environment["DD_PROBE_PHYSICAL_DISCONNECT_WITNESS"] == "1",
              physicalDisconnectObserver == nil
        else { return }
        physicalDisconnectObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let scene = notification.object as? UIWindowScene else { return }
                let nativeID = scene.session.persistentIdentifier
                let snapshot = sceneRegistry.snapshot(nativeSceneID: nativeID)
                eventRecorder.record(ProbeSignal(
                    kind: .assertion,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: snapshot?.logicalSceneID ?? "unregistered",
                        nativeSceneID: nativeID
                    ),
                    activationState: ProbeSceneActivationState(scene.activationState).rawValue,
                    sceneDisconnectGeneration: snapshot?.disconnectGeneration,
                    name: "physical-scene-disconnect-notification",
                    result: .pass,
                    reason: "process-lifetime OS notification witness; registry and driver unchanged"
                ))
            }
        }
        eventRecorder.record(ProbeSignal(
            kind: .assertion,
            name: "physical-scene-disconnect-witness-installed",
            result: .pass
        ))
    }

    static func configureDatadog() {
        ProbeScenarioRunner.emitManifest(resolution.manifest, sink: ProbeArtifactCapture.record)

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
                uiKitViewsPredicate: ProbeFatalContract.isRecovery(scenario?.identifier ?? "")
                    ? nil : ProbeUIKitViewsPredicate(),
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
                urlSessionTracking: scenario?.identifier == ProbeResourceContract.scenarioID
                    ? .init(resourceAttributesProvider: { request, _, _, _ in
                        ProbeResourceAcceptance.attributes(for: request)
                    })
                    : nil,
                trackBackgroundEvents: true,
                longTaskThreshold: ProbeVitalsContract.contains(scenario?.identifier) ? nil
                    : scenario?.identifier == ProbeProcessContract.scenarioID ? 0.5 : 0.1,
                appHangThreshold: scenario?.identifier == ProbeProcessContract.scenarioID ? 0.5 : nil,
                vitalsUpdateFrequency: ProbeVitalsContract.contains(scenario?.identifier) ? .frequent : .average,
                viewEventMapper: { event in
                    var event = event
                    #if DEBUG
                    if ProbeFatalContract.contains(scenario?.identifier ?? "") {
                        event = ProbeFatalAcceptance.annotateView(event)
                    }
                    #endif
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
                    #if DEBUG
                    if ProbeFatalContract.contains(scenario?.identifier ?? "") {
                        ProbeFatalAcceptance.recordPayload(event)
                    }
                    if scenario?.identifier == ProbeLogContract.scenarioID {
                        ProbeLogAcceptance.recordPayloadCheck(event)
                    } else if scenario?.identifier == ProbeErrorContract.scenarioID {
                        ProbeErrorAcceptance.recordPayloadCheck(event)
                    } else if scenario?.identifier == ProbeAttributeContract.scenarioID {
                        ProbeAttributeAcceptance.recordPayloadCheck(event)
                    } else if scenario?.identifier == ProbeTimingContract.scenarioID {
                        ProbeTimingAcceptance.recordPayloadCheck(event)
                    } else if scenario?.identifier == ProbeFlagContract.scenarioID {
                        ProbeFlagAcceptance.recordPayloadCheck(event)
                    }
                    #endif
                    record(errorEvent: event)
                    return event
                },
                longTaskEventMapper: { event in
                    #if DEBUG
                    if scenario?.identifier == ProbeProcessContract.scenarioID {
                        ProbeProcessAcceptance.recordLongTask(event)
                    }
                    #endif
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
                trackMemoryWarnings: !ProbeVitalsContract.contains(scenario?.identifier),
                telemetrySampleRate: 100
            )
        )
        RUMMonitor.shared().debug = true
        RUMMonitor.shared().addAttribute(forKey: Attribute.runID, value: runID)
        RUMMonitor.shared().addAttribute(forKey: Attribute.host, value: "native-swiftui")

        #if DEBUG
        if ProbeFatalContract.contains(scenario?.identifier ?? "") {
            ProbeFatalAcceptance.configure()
        }
        if scenario?.identifier == ProbeLogContract.scenarioID {
            ProbeLogAcceptance.configure()
        }
        if scenario?.identifier == ProbeReplayContract.scenarioID {
            ProbeReplayAcceptance.configure()
        }
        if scenario?.identifier == ProbeWebViewContract.scenarioID {
            ProbeWebViewAcceptance.configure()
        }
        #endif

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
                + "swiftui_navigation_host_native_dismiss_callbacks="
                + "\(usesEXP152NativeDismissCallbacks) "
                + "swiftui_navigation_host_third_party_callback="
                + "\(usesEXP153ThirdPartyCallbackAdapter) "
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
        guard !ProbeFatalContract.contains(scenario?.identifier ?? "") else {
            return
        }
        guard ![ProbeVitalsContract.scenarioID, ProbeVitalsContract.physicalScenarioID, ProbeProcessContract.scenarioID, ProbeResourceContract.scenarioID, ProbeErrorContract.scenarioID, ProbeAttributeContract.scenarioID, ProbeTimingContract.scenarioID, ProbeFlagContract.scenarioID, ProbeTraceContract.scenarioID, ProbeLogContract.scenarioID, ProbeWebViewContract.scenarioID, ProbeReplayContract.scenarioID].contains(scenario?.identifier ?? "") else { return }
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
        let timingState = scenario?.identifier == ProbeTimingContract.scenarioID
            ? ProbeTimingState(
                timings: (event.view.customTimings?.customTimingsInfo ?? [:]).filter { ProbeTimingContract.keys.contains($0.key) },
                loading: event.view.loadingTime
            ) : nil
        #if DEBUG
        let vitals = ProbeVitalsContract.contains(scenario?.identifier)
            ? ProbeVitalsAcceptance.viewObservation(event) : nil
        let process = scenario?.identifier == ProbeProcessContract.scenarioID
            ? ProbeProcessAcceptance.viewObservation(event) : nil
        let fatal = ProbeFatalContract.contains(scenario?.identifier ?? "")
            ? ProbeFatalAcceptance.viewObservation(event) : nil
        let flagState = scenario?.identifier == ProbeFlagContract.scenarioID ? ProbeFlagAcceptance.state(event) : nil
        #else
        let vitals: ProbeVitalsObservation? = nil
        let process: ProbeProcessObservation? = nil
        let fatal: ProbeFatalObservation? = nil
        let flagState: ProbeFlagState? = nil
        #endif
        eventRecorder.record(ProbeRUMEventAdapter.viewSnapshot(event, timingState: timingState, flagState: flagState, process: process, vitals: vitals, fatal: fatal))
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
        #if DEBUG
        let process = scenario?.identifier == ProbeProcessContract.scenarioID
            ? ProbeProcessAcceptance.errorObservation(event) : nil
        #else
        let process: ProbeProcessObservation? = nil
        #endif
        eventRecorder.record(ProbeRUMEventAdapter.error(event, process: process))
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

/// Local physical-run identity evidence, written before SDK initialization.
private enum InstalledCodeReceipt {
    static func writeIfRequested(runID: String) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let requestedRun = environment["MULTISCENE_CODE_IDENTITY_RUN_ID"] else {
            return
        }
        let revision = environment["MULTISCENE_CODE_IDENTITY_REVISION"] ?? ""
        guard requestedRun == runID,
              runID.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil,
              revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              let executable = Bundle.main.executableURL,
              let bundleID = Bundle.main.bundleIdentifier else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let manager = FileManager.default
        let documents = try manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let receipt = documents.appendingPathComponent(runID + ".installed-code.json")
        guard !manager.fileExists(atPath: receipt.path) else { throw CocoaError(.fileWriteFileExists) }
        let root = Bundle.main.bundleURL
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let files = manager.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw CocoaError(.fileReadUnknown)
        }
        var hashes: [String: String] = [:]
        for case let file as URL in files {
            let properties = try file.resourceValues(forKeys: Set(keys))
            guard properties.isRegularFile == true, properties.isSymbolicLink != true else { continue }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 4) ?? Data()
            let magic = header.map { String(format: "%02x", $0) }.joined()
            guard ["cffaedfe", "feedfacf", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"].contains(magic) else {
                continue
            }
            var digest = SHA256()
            digest.update(data: header)
            while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                digest.update(data: chunk)
            }
            let relative = String(file.path.dropFirst(root.path.count + 1))
            hashes[relative] = digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
        let mainPath = String(executable.path.dropFirst(root.path.count + 1))
        guard hashes[mainPath] != nil else { throw CocoaError(.fileReadCorruptFile) }
        let value: [String: Any] = [
            "schemaVersion": 1, "runID": runID, "sourceRevision": revision,
            "processID": ProcessInfo.processInfo.processIdentifier, "bundleIdentifier": bundleID,
            "boundary": "before-sdk-initialization", "executable": mainPath, "binaries": hashes
        ]
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: receipt, options: .atomic)
    }
}


/// Optional fixture evidence for UI tests, whose app stdout is not a reliable
/// collection channel. The external acceptance runner verifies run identity,
/// contiguous sequences and the terminal oracle before accepting this file.
private enum ProbeArtifactCapture {
    private static let lock = NSLock()
    private static let file: FileHandle? = {
        guard ProcessInfo.processInfo.environment["DD_PROBE_CAPTURE_JSONL"] == "1" else {
            return nil
        }
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("ProbeAcceptance", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("probe.jsonl")
            guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
                print("INVALID: probe artifact could not be created")
                return nil
            }
            return try FileHandle(forWritingTo: url)
        } catch {
            print("INVALID: probe artifact capture could not be initialized")
            return nil
        }
    }()

    static func record(_ json: String) {
        print("🔬 [RUM Native Multi-Scene JSONL] \(json)")
        lock.lock()
        defer { lock.unlock() }
        do {
            try file?.write(contentsOf: Data((json + "\n").utf8))
        } catch {
            print("INVALID: probe artifact write failed")
        }
    }
}
