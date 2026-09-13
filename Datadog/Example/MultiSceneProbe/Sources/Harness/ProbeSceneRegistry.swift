/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal enum ProbeSceneActivationState: String, Equatable, CaseIterable {
    case unknown
    case unattached
    case foregroundActive = "foreground-active"
    case foregroundInactive = "foreground-inactive"
    case background

    init(_ activationState: UIScene.ActivationState?) {
        switch activationState {
        case .unattached:
            self = .unattached
        case .foregroundActive:
            self = .foregroundActive
        case .foregroundInactive:
            self = .foregroundInactive
        case .background:
            self = .background
        case nil:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}

internal enum ProbeSceneReadiness: String, Equatable {
    case attached
    case ready
    case disconnected
}

internal struct ProbeSceneHandle: Hashable {
    let logicalSceneID: String
    let nativeSceneID: String
    let disconnectGeneration: UInt64
}

internal struct ProbeScenePresentation: Equatable {
    let activationState: ProbeSceneActivationState
    let geometry: ProbeGeometry?
    let horizontalSizeClass: String?
    let verticalSizeClass: String?

    static func capture(window: UIWindow) -> Self {
        let frame = window.frame
        return ProbeScenePresentation(
            activationState: ProbeSceneActivationState(
                window.windowScene?.activationState
            ),
            geometry: ProbeGeometry(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height
            ),
            horizontalSizeClass: description(
                of: window.traitCollection.horizontalSizeClass
            ),
            verticalSizeClass: description(
                of: window.traitCollection.verticalSizeClass
            )
        )
    }

    private static func description(
        of sizeClass: UIUserInterfaceSizeClass
    ) -> String {
        switch sizeClass {
        case .unspecified:
            return "unspecified"
        case .compact:
            return "compact"
        case .regular:
            return "regular"
        @unknown default:
            return "unknown"
        }
    }
}

/// A non-serializable snapshot of the probe's exact scene state.
///
/// futureExecutionContextID is deliberately an internal seam. It is not copied
/// into ProbeSignal or any RUM attribute.
internal struct ProbeSceneSnapshot: Equatable {
    let logicalSceneID: String
    let nativeSceneID: String
    let disconnectGeneration: UInt64
    let readiness: ProbeSceneReadiness
    let presentation: ProbeScenePresentation
    let currentRoute: [String]
    let hasWindow: Bool
    let futureExecutionContextID: String?
}

internal enum ProbeSceneRegistrationResult: Equatable {
    case registered(ProbeSceneHandle)
    case rejected(reason: String)
}

@MainActor
internal final class ProbeSceneRegistry {
    private final class Entry {
        let logicalSceneID: String
        var nativeSceneID: String
        weak var window: UIWindow?
        var disconnectGeneration: UInt64
        var readiness: ProbeSceneReadiness
        var presentation: ProbeScenePresentation
        var currentRoute: [String]
        var futureExecutionContextID: String?

        init(
            logicalSceneID: String,
            nativeSceneID: String,
            window: UIWindow,
            currentRoute: [String]
        ) {
            self.logicalSceneID = logicalSceneID
            self.nativeSceneID = nativeSceneID
            self.window = window
            self.disconnectGeneration = 0
            self.readiness = .attached
            self.presentation = .capture(window: window)
            self.currentRoute = currentRoute
        }

        var handle: ProbeSceneHandle {
            ProbeSceneHandle(
                logicalSceneID: logicalSceneID,
                nativeSceneID: nativeSceneID,
                disconnectGeneration: disconnectGeneration
            )
        }

        var snapshot: ProbeSceneSnapshot {
            ProbeSceneSnapshot(
                logicalSceneID: logicalSceneID,
                nativeSceneID: nativeSceneID,
                disconnectGeneration: disconnectGeneration,
                readiness: readiness,
                presentation: presentation,
                currentRoute: currentRoute,
                hasWindow: window != nil,
                futureExecutionContextID: futureExecutionContextID
            )
        }
    }

    private var entriesByLogicalSceneID: [String: Entry] = [:]
    private var logicalSceneIDByNativeSceneID: [String: String] = [:]

    func register(
        logicalSceneID: String,
        nativeSceneID: String,
        window: UIWindow,
        currentRoute: [String]
    ) -> ProbeSceneRegistrationResult {
        guard !logicalSceneID.isEmpty, !nativeSceneID.isEmpty else {
            return .rejected(reason: "scene identifiers must not be empty")
        }

        if let mappedLogicalSceneID = logicalSceneIDByNativeSceneID[nativeSceneID],
           mappedLogicalSceneID != logicalSceneID {
            return .rejected(
                reason: "native scene \(nativeSceneID) is already registered "
                    + "as \(mappedLogicalSceneID)"
            )
        }

        if let entry = entriesByLogicalSceneID[logicalSceneID] {
            if entry.nativeSceneID != nativeSceneID {
                guard entry.readiness == .disconnected else {
                    return .rejected(
                        reason: "logical scene \(logicalSceneID) is already connected "
                            + "as \(entry.nativeSceneID)"
                    )
                }
                logicalSceneIDByNativeSceneID.removeValue(
                    forKey: entry.nativeSceneID
                )
                entry.nativeSceneID = nativeSceneID
                entry.futureExecutionContextID = nil
            }

            let wasDisconnected = entry.readiness == .disconnected
            entry.window = window
            entry.presentation = .capture(window: window)
            entry.currentRoute = currentRoute
            if wasDisconnected {
                entry.readiness = .attached
            }
            logicalSceneIDByNativeSceneID[nativeSceneID] = logicalSceneID
            return .registered(entry.handle)
        }

        let entry = Entry(
            logicalSceneID: logicalSceneID,
            nativeSceneID: nativeSceneID,
            window: window,
            currentRoute: currentRoute
        )
        entriesByLogicalSceneID[logicalSceneID] = entry
        logicalSceneIDByNativeSceneID[nativeSceneID] = logicalSceneID
        return .registered(entry.handle)
    }

    @discardableResult
    func markReady(_ handle: ProbeSceneHandle) -> ProbeSceneSnapshot? {
        guard let entry = liveEntry(for: handle), entry.window != nil else {
            return nil
        }
        entry.readiness = .ready
        return entry.snapshot
    }

    @discardableResult
    func updateRoute(
        _ route: [String],
        for handle: ProbeSceneHandle
    ) -> ProbeSceneSnapshot? {
        guard let entry = liveEntry(for: handle) else {
            return nil
        }
        entry.currentRoute = route
        return entry.snapshot
    }

    @discardableResult
    func updatePresentation(
        _ presentation: ProbeScenePresentation,
        for handle: ProbeSceneHandle
    ) -> ProbeSceneSnapshot? {
        guard let entry = liveEntry(for: handle) else {
            return nil
        }
        entry.presentation = presentation
        return entry.snapshot
    }

    @discardableResult
    func updatePresentation(
        from window: UIWindow,
        for handle: ProbeSceneHandle
    ) -> ProbeSceneSnapshot? {
        guard let entry = liveEntry(for: handle) else {
            return nil
        }
        if let resolvedNativeSceneID =
            window.windowScene?.session.persistentIdentifier,
           resolvedNativeSceneID != handle.nativeSceneID {
            return nil
        }
        entry.window = window
        entry.presentation = .capture(window: window)
        return entry.snapshot
    }

    @discardableResult
    func associateFutureExecutionContextID(
        _ executionContextID: String?,
        with handle: ProbeSceneHandle
    ) -> ProbeSceneSnapshot? {
        guard let entry = liveEntry(for: handle) else {
            return nil
        }
        entry.futureExecutionContextID = executionContextID
        return entry.snapshot
    }

    @discardableResult
    func disconnect(_ handle: ProbeSceneHandle) -> ProbeSceneSnapshot? {
        guard let entry = liveEntry(for: handle) else {
            return nil
        }
        entry.readiness = .disconnected
        entry.window = nil
        entry.disconnectGeneration &+= 1
        return entry.snapshot
    }

    @discardableResult
    func disconnect(nativeSceneID: String) -> ProbeSceneSnapshot? {
        guard
            let logicalSceneID = logicalSceneIDByNativeSceneID[nativeSceneID],
            let entry = entriesByLogicalSceneID[logicalSceneID],
            entry.nativeSceneID == nativeSceneID,
            entry.readiness != .disconnected
        else {
            return nil
        }
        return disconnect(entry.handle)
    }

    func handle(logicalSceneID: String) -> ProbeSceneHandle? {
        guard
            let entry = entriesByLogicalSceneID[logicalSceneID],
            entry.readiness != .disconnected
        else {
            return nil
        }
        return entry.handle
    }

    func snapshot(logicalSceneID: String) -> ProbeSceneSnapshot? {
        entriesByLogicalSceneID[logicalSceneID]?.snapshot
    }

    func snapshot(nativeSceneID: String) -> ProbeSceneSnapshot? {
        guard
            let logicalSceneID = logicalSceneIDByNativeSceneID[nativeSceneID]
        else {
            return nil
        }
        return entriesByLogicalSceneID[logicalSceneID]?.snapshot
    }

    func window(for handle: ProbeSceneHandle) -> UIWindow? {
        liveEntry(for: handle)?.window
    }

    private func liveEntry(for handle: ProbeSceneHandle) -> Entry? {
        guard
            let entry = entriesByLogicalSceneID[handle.logicalSceneID],
            entry.nativeSceneID == handle.nativeSceneID,
            entry.disconnectGeneration == handle.disconnectGeneration,
            entry.readiness != .disconnected
        else {
            return nil
        }
        return entry
    }
}
