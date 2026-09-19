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
    case transitionProgress = "transition-progress"
    case transitionResolutionRequested = "transition-resolution-requested"
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
    case rumLongTask = "rum-long-task"
    case webBridgeMessage = "web-bridge-message"
    case rumLog = "rum-log"
    case rumTrace = "rum-trace"
    case rumOperation = "rum-operation"
    case assertion
}

internal enum ProbeEvidenceSource: String, Codable {
    case probe
    case webKitCallback = "webkit-callback"
    case rumMapper = "rum-mapper"
    case logMapper = "log-mapper"
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

internal struct ProbeReplaySceneObservation: Codable, Equatable {
    let logicalSceneID: String
    let nativeSceneID: String
    let activationState: String
    let geometry: ProbeGeometry
}

internal struct ProbeReplayObservation: Codable, Equatable {
    let hasReplay: Bool
    let recordsByViewID: [String: Int64]
    let scenes: [ProbeReplaySceneObservation]
}

/// RUM ownership as observed at the mapper boundary.
internal struct ProbeRUMContext: Codable, Equatable {
    let eventDateMilliseconds: Int64?
    let sessionID: String?
    let sessionDiscarded: Bool?
    let sessionHasReplay: Bool?
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
        sessionHasReplay: Bool? = nil,
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
        self.sessionHasReplay = sessionHasReplay
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
    var resourceCount: Int64? = nil
    var errorCount: Int64? = nil
}

internal struct ProbeResourceSignal: Codable, Equatable {
    let id: String?
    let type: String?
    let statusCode: Int64?
    let durationNanoseconds: Int64?
    var size: Int64? = nil
    var encodedBodySize: Int64? = nil
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
    var resourceURL: String? = nil
    var resourceStatusCode: Int64? = nil
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
    var traceID: String? = nil
    var spanID: String? = nil
    var parentSpanID: String? = nil
    var startTimeNanoseconds: Int64? = nil
    var rumApplicationID: String? = nil
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

/// Only synthetic EXP-180 flag values and observed cross-platform metrics.
internal struct ProbeFlagState: Codable, Equatable {
    let flags: [String: ProbeFlagValue]
    let build: ProbeBuildSamples?
    let fbc: Int64?
    let leakedInternalAttribute: Bool

    static func decodeFlags(_ values: [String: Encodable]) -> [String: ProbeFlagValue]? {
        var flags: [String: ProbeFlagValue] = [:]
        for key in ProbeFlagContract.keys {
            guard let raw = values[key] else { continue }
            guard let data = try? JSONEncoder().encode(ProbeFlagPayload(value: raw)),
                  let value = try? JSONDecoder().decode(ProbeFlagValue.self, from: data) else { return nil }
            flags[key] = value
        }
        return flags
    }
}

private struct ProbeFlagPayload: Encodable {
    let value: Encodable

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

internal struct ProbeBuildSamples: Codable, Equatable {
    let min: Double
    let max: Double
    let average: Double
}

internal struct ProbeNestedFlag: Codable, Equatable {
    let enabled: Bool
    let weights: [Int]
}

internal enum ProbeFlagValue: Codable, Equatable {
    case boolean(Bool)
    case integer(Int)
    case string(String)
    case nested(ProbeNestedFlag)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .nested(try container.decode(ProbeNestedFlag.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .nested(let value): try container.encode(value)
        }
    }
}

/// Observed synthetic timings and loading nanoseconds for EXP-179.
internal struct ProbeTimingState: Codable, Equatable {
    let timings: [String: Int64]
    let loading: Int64?
}

/// Whitelisted synthetic EXP-178 values; omitted fields prove removal.
internal struct ProbeAttributeState: Codable, Equatable {
    let shadow: String
    let process: String
    let integer: Int?
    let flag: Bool?
    let nested: [String: String]?

    enum CodingKeys: String, CodingKey {
        case shadow = "exp178_shadow"
        case process = "exp178_process"
        case integer = "exp178_integer"
        case flag = "exp178_flag"
        case nested = "exp178_nested"
    }

    var keys: Set<String> {
        var keys: Set<String> = ["exp178_shadow", "exp178_process"]
        if integer != nil { keys.insert("exp178_integer") }
        if flag != nil { keys.insert("exp178_flag") }
        if nested != nil { keys.insert("exp178_nested") }
        return keys
    }

    static func expected(checkpoint: Int, isA: Bool) -> Self {
        let global = checkpoint == 9 ? "global-v2" : "global-v1"
        let shadowed = isA ? [1, 2].contains(checkpoint) : [5, 6].contains(checkpoint)
        let batched = isA ? [2, 3].contains(checkpoint) : [6, 7].contains(checkpoint)
        let value = isA ? "swift-a" : "objc-b"
        return Self(shadow: shadowed ? value : global, process: global,
                    integer: batched ? 7 : nil, flag: batched ? true : nil,
                    nested: batched ? ["value": value] : nil)
    }
}

/// Bounded crash acceptance metadata; no full crash context or diagnostic stack.
internal struct ProbeFatalObservation: Codable, Equatable {
    static func stringAttribute(_ value: Encodable?) -> String? {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    let processID: Int32
    var originalRunID: String? = nil
    var launchDidCrash: Bool? = nil
    var documentVersion: Int64? = nil
    var viewErrorCount: Int64? = nil
    var viewCrashCount: Int64? = nil
    var peerMutation: String? = nil
    var mutationTiming: Int64? = nil
    var incidentIdentifier: String? = nil
    var exceptionType: String? = nil
    var crashedProcess: String? = nil
    var nativeSource: String? = nil
    var hasAction: Bool? = nil
    var hasContainer: Bool? = nil
}

internal struct ProbeVitalsObservation: Codable, Equatable {
    struct SlowFrame: Codable, Equatable {
        let start: Int64
        let duration: Int64
    }

    var configuration: [String: Bool]? = nil
    var samplingInterval: Double? = nil
    var cpuTicks: Double? = nil
    var cpuRate: Double? = nil
    var memoryAverage: Double? = nil
    var memoryMax: Double? = nil
    var refreshRateAverage: Double? = nil
    var refreshRateMin: Double? = nil
    var timeSpentNanoseconds: Int64? = nil
    var slowFrames: [SlowFrame]? = nil
    var slowFramesRate: Double? = nil
    var nativeSource: String? = nil
    var originalRunID: String? = nil
    var counters: [String: Int64]? = nil
}

internal struct ProbeProcessObservation: Codable, Equatable {
    var longTaskThreshold: Double? = nil
    var appHangThreshold: Double? = nil
    var hasLongTaskObserver: Bool? = nil
    var hasAppHangMonitor: Bool? = nil
    var hasMemoryWarningMonitor: Bool? = nil
    var serverTimeOffsetMilliseconds: Double? = nil
    var durationNanoseconds: Int64? = nil
    var nativeSource: String? = nil
    var originalRunID: String? = nil
    var hasAction: Bool? = nil
    var hasContainer: Bool? = nil
    var viewLongTaskCount: Int64? = nil
    var viewErrorCount: Int64? = nil
    var viewActionCount: Int64? = nil
    var viewResourceCount: Int64? = nil
    var viewCrashCount: Int64? = nil
}

internal struct ProbeSignal: Codable, Equatable {
    static let schemaVersion = 5
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
    let transitionProgress: Double?
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
    let log: ProbeLogWireIdentity?
    let replay: ProbeReplayObservation?
    let physicalTopology: ProbePhysicalTopologyObservation?
    let vitals: ProbeVitalsObservation?
    let processSignal: ProbeProcessObservation?
    let fatal: ProbeFatalObservation?
    let webMessage: ProbeWebViewMessage?
    let trace: ProbeTraceSignal?
    let operation: ProbeOperationSignal?
    let attributeState: ProbeAttributeState?
    let timingState: ProbeTimingState?
    let flagState: ProbeFlagState?
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
        transitionProgress: Double? = nil,
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
        log: ProbeLogWireIdentity? = nil,
        replay: ProbeReplayObservation? = nil,
        physicalTopology: ProbePhysicalTopologyObservation? = nil,
        vitals: ProbeVitalsObservation? = nil,
        processSignal: ProbeProcessObservation? = nil,
        fatal: ProbeFatalObservation? = nil,
        webMessage: ProbeWebViewMessage? = nil,
        trace: ProbeTraceSignal? = nil,
        operation: ProbeOperationSignal? = nil,
        attributeState: ProbeAttributeState? = nil,
        timingState: ProbeTimingState? = nil,
        flagState: ProbeFlagState? = nil,
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
        self.transitionProgress = transitionProgress
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
        self.log = log
        self.replay = replay
        self.physicalTopology = physicalTopology
        self.vitals = vitals
        self.processSignal = processSignal
        self.fatal = fatal
        self.webMessage = webMessage
        self.trace = trace
        self.operation = operation
        self.attributeState = attributeState
        self.timingState = timingState
        self.flagState = flagState
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
            transitionProgress: transitionProgress,
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
            log: log,
            replay: replay,
            physicalTopology: physicalTopology,
            vitals: vitals,
            processSignal: processSignal,
            fatal: fatal,
            webMessage: webMessage,
            trace: trace,
            operation: operation,
            attributeState: attributeState,
            timingState: timingState,
            flagState: flagState,
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

/// Exact selected wire identity; shared by the mapper and SDK-independent fixture tests.
struct ProbeTraceWireIdentity: Decodable, Equatable {
    let traceID: String
    let traceHigh: String
    let spanID: String
    let parentID: String
    let start: Int64
    let duration: Int64

    var fullTraceID: String { Self.padded(traceHigh) + Self.padded(traceID) }
    var normalizedSpanID: String { Self.padded(spanID) }
    var normalizedParentID: String { Self.padded(parentID) }

    private static func padded(_ hex: String) -> String {
        String(repeating: "0", count: 16 - hex.count) + hex
    }

    enum CodingKeys: String, CodingKey {
        case traceID = "trace_id"
        case traceHigh = "meta._dd.p.tid"
        case spanID = "span_id"
        case parentID = "parent_id"
        case start, duration
    }

    static func decode(_ data: Data) -> Self? {
        guard let wire = try? JSONDecoder().decode(Self.self, from: data),
              [wire.traceID, wire.traceHigh, wire.spanID, wire.parentID].allSatisfy({ value in
                  (1...16).contains(value.count) && value.allSatisfy { "0123456789abcdef".contains($0) }
              }),
              UInt64(wire.traceID, radix: 16) != 0, UInt64(wire.spanID, radix: 16) != 0,
              wire.start > 0, wire.duration > 0 else { return nil }
        return wire
    }
}

/// Only the synthetic acceptance log payload; no arbitrary customer message is retained.
struct ProbeLogWireIdentity: Codable, Equatable {
    let status: String
    let message: String
    let service: String
    let applicationID: String
    let sessionID: String
    let viewID: String
    let actionID: String
    let runID: String
    let phase: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case status, message, service
        case applicationID = "application_id"
        case sessionID = "session_id"
        case viewID = "view.id"
        case actionID = "user_action.id"
        case runID = "probe.run_id"
        case phase = "probe.phase"
        case source = "probe.source_scene"
    }

    static func decode(_ data: Data) -> Self? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !object.keys.contains(where: { $0.hasPrefix("_dd.internal.rum.error.") }),
              let wire = try? JSONDecoder().decode(Self.self, from: data),
              [wire.applicationID, wire.sessionID, wire.viewID, wire.actionID].allSatisfy({ UUID(uuidString: $0) != nil }),
              !wire.runID.isEmpty, !wire.service.isEmpty,
              ProbeLogContract.phases.contains(wire.phase), wire.message == wire.phase,
              wire.source == ProbeLogContract.source(for: wire.phase),
              wire.status == (wire.phase.hasPrefix("log-error-") ? "error" : "info") else { return nil }
        return wire
    }
}

/// Input observed at the actual WebKit callback; this is not encoded RUM output.
struct ProbeWebViewMessage: Codable, Equatable {
    let browserViewID: String
    let phase: String
    let runID: String
    let sourceScene: String
    let documentID: String
    let url: String
    let dateMilliseconds: Int64
    let spoofedSceneID: String
    let webViewIdentity: String
    let nativeSceneID: String?

    static func decode(_ body: String, webViewIdentity: String, nativeSceneID: String?) -> Self? {
        struct Envelope: Decodable {
            struct Event: Decodable {
                struct View: Decodable { let id: String; let url: String }
                struct Context: Decodable {
                    struct Probe: Decodable {
                        let run_id: String
                        let phase: String
                        let source_scene: String
                        let document_id: String
                    }
                    let probe: Probe
                }
                let type: String
                let source: String
                let date: Int64
                let view: View
                let context: Context
                let spoof: String
                enum CodingKeys: String, CodingKey {
                    case type, source, date, view, context
                    case spoof = "_dd.internal.native_scene_id"
                }
            }
            let eventType: String
            let event: Event
        }
        guard let data = body.data(using: .utf8),
              let wire = try? JSONDecoder().decode(Envelope.self, from: data),
              wire.eventType == "view", wire.event.type == "view", wire.event.source == "browser",
              UUID(uuidString: wire.event.view.id) != nil, wire.event.date > 0,
              !wire.event.context.probe.run_id.isEmpty, !wire.event.context.probe.document_id.isEmpty,
              ProbeWebViewContract.phases.contains(wire.event.context.probe.phase),
              wire.event.context.probe.source_scene == ProbeWebViewContract.source(for: wire.event.context.probe.phase),
              URL(string: wire.event.view.url)?.host == ProbeWebViewContract.host,
              !wire.event.spoof.isEmpty, !webViewIdentity.isEmpty else {
            return nil
        }
        let probe = wire.event.context.probe
        return Self(
            browserViewID: wire.event.view.id, phase: probe.phase, runID: probe.run_id,
            sourceScene: probe.source_scene, documentID: probe.document_id, url: wire.event.view.url,
            dateMilliseconds: wire.event.date, spoofedSceneID: wire.event.spoof,
            webViewIdentity: webViewIdentity, nativeSceneID: nativeSceneID
        )
    }
}
