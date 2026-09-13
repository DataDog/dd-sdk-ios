/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal enum ProbeSemanticResultState: String, Codable, CaseIterable {
    case pass = "PASS"
    case fail = "FAIL"
    case skipped = "SKIPPED"
    case inconclusive = "INCONCLUSIVE"
}

internal enum ProbeSignalKind: String, Codable, CaseIterable {
    case capability
    case sceneReady = "scene-ready"
    case sceneLifecycle = "scene-lifecycle"
    case sceneGeometry = "scene-geometry"
    case navigationPathMutation = "navigation-path-mutation"
    case intervalBegan = "interval-began"
    case intervalEnded = "interval-ended"
    case gestureAttempted = "gesture-attempted"
    case transitionBegan = "transition-began"
    case transitionResolved = "transition-resolved"
    case stepStarted = "step-started"
    case stepAcknowledged = "step-acknowledged"
    case destinationAppearanceObserved = "destination-appearance-observed"
    case destinationMaterialized = "destination-materialized"
    case rumSessionStarted = "rum-session-started"
    case rumViewSnapshot = "rum-view-snapshot"
    case rumAction = "rum-action"
    case rumResource = "rum-resource"
    case rumError = "rum-error"
    case rumTrace = "rum-trace"
    case rumOperation = "rum-operation"
    case assertion
}

internal enum ProbeEvidenceSource: String, Codable {
    case probe
    case rumMapper = "rum-mapper"
    case traceMapper = "trace-mapper"
    case internalHook = "internal-hook"
}

internal struct ProbeSemanticContext: Codable, Equatable {
    let logicalSceneID: String
    let nativeSceneID: String?
    let screen: String?
    let occurrence: Int?

    init(
        logicalSceneID: String,
        nativeSceneID: String? = nil,
        screen: String? = nil,
        occurrence: Int? = nil
    ) {
        self.logicalSceneID = logicalSceneID
        self.nativeSceneID = nativeSceneID
        self.screen = screen
        self.occurrence = occurrence
    }
}

/// Where probe-owned work was requested. This is never proof of RUM ownership.
internal struct ProbeSourceContext: Codable, Equatable {
    let logicalSceneID: String?
    let nativeSceneID: String?
    let screen: String?
    let occurrence: Int?
    let phase: String?
    let uptime: Double?
    let readerControlGeneration: Int?

    init(
        logicalSceneID: String? = nil,
        nativeSceneID: String? = nil,
        screen: String? = nil,
        occurrence: Int? = nil,
        phase: String? = nil,
        uptime: Double? = nil,
        readerControlGeneration: Int? = nil
    ) {
        self.logicalSceneID = logicalSceneID
        self.nativeSceneID = nativeSceneID
        self.screen = screen
        self.occurrence = occurrence
        self.phase = phase
        self.uptime = uptime
        self.readerControlGeneration = readerControlGeneration
    }
}

/// RUM ownership as observed at the mapper boundary.
internal struct ProbeRUMContext: Codable, Equatable {
    let eventDateMilliseconds: Int64?
    let sessionID: String?
    let sessionDiscarded: Bool?
    let viewID: String?
    let viewName: String?
    let viewURL: String?
    let viewActive: Bool?
    let viewDocumentVersion: Int64?
    let viewTimeSpentNanoseconds: Int64?
    let actionIDs: [String]?

    init(
        eventDateMilliseconds: Int64? = nil,
        sessionID: String? = nil,
        sessionDiscarded: Bool? = nil,
        viewID: String? = nil,
        viewName: String? = nil,
        viewURL: String? = nil,
        viewActive: Bool? = nil,
        viewDocumentVersion: Int64? = nil,
        viewTimeSpentNanoseconds: Int64? = nil,
        actionIDs: [String]? = nil
    ) {
        self.eventDateMilliseconds = eventDateMilliseconds
        self.sessionID = sessionID
        self.sessionDiscarded = sessionDiscarded
        self.viewID = viewID
        self.viewName = viewName
        self.viewURL = viewURL
        self.viewActive = viewActive
        self.viewDocumentVersion = viewDocumentVersion
        self.viewTimeSpentNanoseconds = viewTimeSpentNanoseconds
        self.actionIDs = actionIDs
    }
}

internal struct ProbeActionSignal: Codable, Equatable {
    let id: String?
    let type: String?
    let target: String?
    let loadingTimeNanoseconds: Int64?
}

internal struct ProbeResourceSignal: Codable, Equatable {
    let id: String?
    let type: String?
    let statusCode: Int64?
    let durationNanoseconds: Int64?
    let method: String?
    let url: String?
    let traceID: String?
    let spanID: String?
    let parentSpanID: String?
}

/// Deliberately excludes error messages and stack traces to avoid recording customer data.
internal struct ProbeErrorSignal: Codable, Equatable {
    let id: String?
    let source: String?
    let type: String?
    let category: String?
    let handling: String?
    let isCrash: Bool?
    let traceID: String?
    let spanID: String?
    let parentSpanID: String?
}

internal struct ProbeTraceSignal: Codable, Equatable {
    let operationName: String?
    let serviceName: String?
    let resourceName: String?
    let startTimeMilliseconds: Int64?
    let durationNanoseconds: Int64?
    let isError: Bool?
    let rumSessionID: String?
    let rumViewID: String?
    let rumActionIDs: [String]?
}

internal struct ProbeOperationSignal: Codable, Equatable {
    let vitalID: String?
    let name: String?
    let key: String?
    let step: String?
    let failureReason: String?
}

internal struct ProbeGeometry: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

internal struct ProbeSignal: Codable, Equatable {
    static let schemaVersion = 3
    static let supportedSchemaVersions = 1 ... schemaVersion

    let schemaVersion: Int
    let sequence: UInt64
    let timestampMilliseconds: Int64
    let runID: String
    let scenarioID: String
    let kind: ProbeSignalKind
    let evidenceSource: ProbeEvidenceSource
    let semanticContext: ProbeSemanticContext?
    let sourceContext: ProbeSourceContext?
    let rumContext: ProbeRUMContext?
    let scenePhase: String?
    let activationState: String?
    let sceneDisconnectGeneration: UInt64?
    let geometry: ProbeGeometry?
    let horizontalSizeClass: String?
    let verticalSizeClass: String?
    let previousNavigationPath: [String]?
    let navigationPath: [String]?
    let mutation: UInt64?
    let interval: String?
    let transitionID: String?
    let interactive: Bool?
    let outcome: ProbeTransitionOutcome?
    let stepIndex: Int?
    let stepKind: ProbeStepKind?
    let acknowledgedSignalSequence: UInt64?
    let eventID: String?
    let name: String?
    let capability: ProbeCapability?
    let available: Bool?
    let action: ProbeActionSignal?
    let resource: ProbeResourceSignal?
    let error: ProbeErrorSignal?
    let trace: ProbeTraceSignal?
    let operation: ProbeOperationSignal?
    let result: ProbeSemanticResultState?
    let reason: String?

    init(
        kind: ProbeSignalKind,
        evidenceSource: ProbeEvidenceSource = .probe,
        sequence: UInt64 = 0,
        timestampMilliseconds: Int64 = 0,
        runID: String = "",
        scenarioID: String = "",
        semanticContext: ProbeSemanticContext? = nil,
        sourceContext: ProbeSourceContext? = nil,
        rumContext: ProbeRUMContext? = nil,
        scenePhase: String? = nil,
        activationState: String? = nil,
        sceneDisconnectGeneration: UInt64? = nil,
        geometry: ProbeGeometry? = nil,
        horizontalSizeClass: String? = nil,
        verticalSizeClass: String? = nil,
        previousNavigationPath: [String]? = nil,
        navigationPath: [String]? = nil,
        mutation: UInt64? = nil,
        interval: String? = nil,
        transitionID: String? = nil,
        interactive: Bool? = nil,
        outcome: ProbeTransitionOutcome? = nil,
        stepIndex: Int? = nil,
        stepKind: ProbeStepKind? = nil,
        acknowledgedSignalSequence: UInt64? = nil,
        eventID: String? = nil,
        name: String? = nil,
        capability: ProbeCapability? = nil,
        available: Bool? = nil,
        action: ProbeActionSignal? = nil,
        resource: ProbeResourceSignal? = nil,
        error: ProbeErrorSignal? = nil,
        trace: ProbeTraceSignal? = nil,
        operation: ProbeOperationSignal? = nil,
        result: ProbeSemanticResultState? = nil,
        reason: String? = nil
    ) {
        self.schemaVersion = Self.schemaVersion
        self.sequence = sequence
        self.timestampMilliseconds = timestampMilliseconds
        self.runID = runID
        self.scenarioID = scenarioID
        self.kind = kind
        self.evidenceSource = evidenceSource
        self.semanticContext = semanticContext
        self.sourceContext = sourceContext
        self.rumContext = rumContext
        self.scenePhase = scenePhase
        self.activationState = activationState
        self.sceneDisconnectGeneration = sceneDisconnectGeneration
        self.geometry = geometry
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
        self.previousNavigationPath = previousNavigationPath
        self.navigationPath = navigationPath
        self.mutation = mutation
        self.interval = interval
        self.transitionID = transitionID
        self.interactive = interactive
        self.outcome = outcome
        self.stepIndex = stepIndex
        self.stepKind = stepKind
        self.acknowledgedSignalSequence = acknowledgedSignalSequence
        self.eventID = eventID
        self.name = name
        self.capability = capability
        self.available = available
        self.action = action
        self.resource = resource
        self.error = error
        self.trace = trace
        self.operation = operation
        self.result = result
        self.reason = reason
    }

    func enveloped(
        sequence: UInt64,
        timestampMilliseconds: Int64,
        runID: String,
        scenarioID: String
    ) -> ProbeSignal {
        ProbeSignal(
            kind: kind,
            evidenceSource: evidenceSource,
            sequence: sequence,
            timestampMilliseconds: timestampMilliseconds,
            runID: runID,
            scenarioID: scenarioID,
            semanticContext: semanticContext,
            sourceContext: sourceContext,
            rumContext: rumContext,
            scenePhase: scenePhase,
            activationState: activationState,
            sceneDisconnectGeneration: sceneDisconnectGeneration,
            geometry: geometry,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            previousNavigationPath: previousNavigationPath,
            navigationPath: navigationPath,
            mutation: mutation,
            interval: interval,
            transitionID: transitionID,
            interactive: interactive,
            outcome: outcome,
            stepIndex: stepIndex,
            stepKind: stepKind,
            acknowledgedSignalSequence: acknowledgedSignalSequence,
            eventID: eventID,
            name: name,
            capability: capability,
            available: available,
            action: action,
            resource: resource,
            error: error,
            trace: trace,
            operation: operation,
            result: result,
            reason: reason
        )
    }
}

internal struct ProbeSignalRecord: Codable, Equatable {
    let type: String
    let signal: ProbeSignal

    init(signal: ProbeSignal) {
        self.type = "signal"
        self.signal = signal
    }
}
