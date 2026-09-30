// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
// Appended only to the isolated native input observer source for H10 preparation.

internal struct ProbeSceneBackgroundInteraction: Codable, Equatable {
    let logicalSceneID: String
    let windowIdentity: String
    let rootIdentity: String
    let windowEnabled: Bool
    let rootEnabled: Bool
}

internal struct ProbeSceneBackgroundWitness: Encodable {
    let schemaVersion = 1
    let runID: String
    let scenarioID = "windows.isolated-background-foreground"
    let profile = "physical-isolated-background-foreground"
    let notificationNames: [String: String]
    let snapshot: ProbePhysicalInputSnapshot
    let interaction: [ProbeSceneBackgroundInteraction]
}

extension ProbePhysicalOperationInput {
    /// Actual MainActor observations only. This does not arm a scenario, emit SDK
    /// work, validate lifecycle order, or authorize input and cleanup.
    func snapshotForBackgroundCycle(runID: String) -> ProbeSceneBackgroundWitness {
        let value = snapshot()
        let interaction = ["scene-A", "scene-B"].compactMap { label -> ProbeSceneBackgroundInteraction? in
            guard let entry = entries[label], let window = entry.window,
                  let root = window.rootViewController else { return nil }
            return .init(logicalSceneID: label, windowIdentity: Self.identity(window),
                         rootIdentity: Self.identity(root), windowEnabled: window.isUserInteractionEnabled,
                         rootEnabled: root.viewIfLoaded?.isUserInteractionEnabled == true)
        }
        return .init(runID: runID, notificationNames: [
            "sceneActivate": UIScene.didActivateNotification.rawValue,
            "sceneDeactivate": UIScene.willDeactivateNotification.rawValue,
            "sceneForeground": UIScene.willEnterForegroundNotification.rawValue,
            "sceneBackground": UIScene.didEnterBackgroundNotification.rawValue,
            "sceneDisconnect": UIScene.didDisconnectNotification.rawValue,
            "windowVisible": UIWindow.didBecomeVisibleNotification.rawValue,
            "windowHidden": UIWindow.didBecomeHiddenNotification.rawValue,
            "windowKey": UIWindow.didBecomeKeyNotification.rawValue,
            "windowResignKey": UIWindow.didResignKeyNotification.rawValue,
            "appResignActive": UIApplication.willResignActiveNotification.rawValue,
            "appActive": UIApplication.didBecomeActiveNotification.rawValue,
            "appBackground": UIApplication.didEnterBackgroundNotification.rawValue,
            "appForeground": UIApplication.willEnterForegroundNotification.rawValue
        ], snapshot: value, interaction: interaction)
    }
}
