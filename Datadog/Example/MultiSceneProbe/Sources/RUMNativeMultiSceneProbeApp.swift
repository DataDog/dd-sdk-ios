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
            ProbeWindowRoot(window: window)
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
    enum Attribute {
        static let runID = "probe.run_id"
        static let host = "probe.host"
        static let sourceScene = "probe.source_scene"
        static let sceneSessionID = "probe.scene_session_id"
        static let screen = "probe.screen"
        static let phase = "probe.phase"
        static let uptime = "probe.uptime"
    }

    static let serviceName = "ios-sdk-native-multi-scene-probe"
    static let runID = ProcessInfo.processInfo.environment["DD_MULTI_SCENE_RUN_ID"]
        ?? UUID().uuidString.lowercased()
    static let automaticallyNavigates =
        ProcessInfo.processInfo.environment["DD_MULTI_SCENE_AUTORUN_SWIFTUI_DETAIL"] == "1"
    static let automaticallyOpensSecondWindow =
        ProcessInfo.processInfo.environment["DD_MULTI_SCENE_AUTORUN_OPEN_SECOND_WINDOW"] == "1"

    private static let logger = Logger(
        subsystem: "com.datadoghq.rum-native-multi-scene-probe",
        category: "probe"
    )

    static func configureDatadog() {
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
                swiftUIViewsPredicate: DefaultSwiftUIRUMViewsPredicate(),
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
                onSessionStart: { sessionID, isDiscarded in
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
                + "automatic_detail=\(automaticallyNavigates) "
                + "automatic_second_window=\(automaticallyOpensSecondWindow)"
        )
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

    private static func record(viewEvent event: RUMViewEvent) {
        record(
            "payload type=view session=\(event.session.id) view=\(event.view.id) "
                + "name=\(event.view.name ?? "nil") "
                + "active=\(String(describing: event.view.isActive))"
        )
    }

    private static func record(actionEvent event: RUMActionEvent) {
        record(
            "payload type=action session=\(event.session.id) view=\(event.view.id) "
                + "action=\(event.action.id) name=\(event.view.name ?? "nil") "
                + "target=\(event.action.target?.name ?? "nil")"
        )
    }

    private static func record(resourceEvent event: RUMResourceEvent) {
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
