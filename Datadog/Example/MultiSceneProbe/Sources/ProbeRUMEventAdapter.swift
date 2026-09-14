/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogRUM
import DatadogTrace

internal enum ProbeRUMEventAdapter {
    static func sessionStarted(
        sessionID: String,
        isDiscarded: Bool
    ) -> ProbeSignal {
        ProbeSignal(
            kind: .rumSessionStarted,
            evidenceSource: .rumMapper,
            rumContext: ProbeRUMContext(
                sessionID: sessionID,
                sessionDiscarded: isDiscarded
            )
        )
    }

    static func viewSnapshot(_ event: RUMViewEvent) -> ProbeSignal {
        ProbeSignal(
            kind: .rumViewSnapshot,
            evidenceSource: .rumMapper,
            semanticContext: semanticContext(from: event.context?.contextInfo),
            rumContext: ProbeRUMContext(
                eventDateMilliseconds: event.date,
                sessionID: event.session.id,
                viewID: event.view.id,
                viewName: event.view.name,
                viewURL: event.view.url,
                viewActive: event.view.isActive,
                viewDocumentVersion: event.dd.documentVersion,
                viewTimeSpentNanoseconds: event.view.timeSpent
            )
        )
    }

    static func action(_ event: RUMActionEvent) -> ProbeSignal {
        let source = sourceContext(from: event.context?.contextInfo)
        return ProbeSignal(
            kind: .rumAction,
            evidenceSource: .rumMapper,
            sourceContext: source,
            rumContext: ProbeRUMContext(
                eventDateMilliseconds: event.date,
                sessionID: event.session.id,
                viewID: event.view.id,
                viewName: event.view.name,
                viewURL: event.view.url,
                actionIDs: event.action.id.map { [$0] }
            ),
            eventID: event.action.id,
            name: source?.phase ?? event.action.target?.name,
            action: ProbeActionSignal(
                id: event.action.id,
                type: event.action.type.rawValue,
                target: event.action.target?.name,
                loadingTimeNanoseconds: event.action.loadingTime
            )
        )
    }

    static func resource(_ event: RUMResourceEvent) -> ProbeSignal {
        let source = sourceContext(from: event.context?.contextInfo)
        let correlatedActionIDs: [String]?
        switch event.action?.id {
        case .string(let value):
            correlatedActionIDs = [value]
        case .stringsArray(let values):
            correlatedActionIDs = values
        case nil:
            correlatedActionIDs = nil
        }
        return ProbeSignal(
            kind: .rumResource,
            evidenceSource: .rumMapper,
            sourceContext: source,
            rumContext: ProbeRUMContext(
                eventDateMilliseconds: event.date,
                sessionID: event.session.id,
                viewID: event.view.id,
                viewName: event.view.name,
                viewURL: event.view.url,
                actionIDs: correlatedActionIDs
            ),
            eventID: event.resource.id,
            name: source?.phase,
            resource: ProbeResourceSignal(
                id: event.resource.id,
                type: event.resource.type.rawValue,
                statusCode: event.resource.statusCode,
                durationNanoseconds: event.resource.duration,
                method: event.resource.method?.rawValue,
                url: event.resource.url,
                traceID: event.dd.traceId,
                spanID: event.dd.spanId,
                parentSpanID: event.dd.parentSpanId
            )
        )
    }

    static func error(_ event: RUMErrorEvent) -> ProbeSignal {
        let source = sourceContext(from: event.context?.contextInfo)
        let correlatedActionIDs: [String]?
        switch event.action?.id {
        case .string(let value):
            correlatedActionIDs = [value]
        case .stringsArray(let values):
            correlatedActionIDs = values
        case nil:
            correlatedActionIDs = nil
        }
        return ProbeSignal(
            kind: .rumError,
            evidenceSource: .rumMapper,
            sourceContext: source,
            rumContext: ProbeRUMContext(
                eventDateMilliseconds: event.date,
                sessionID: event.session.id,
                viewID: event.view.id,
                viewName: event.view.name,
                viewURL: event.view.url,
                actionIDs: correlatedActionIDs
            ),
            eventID: event.error.id,
            name: source?.phase ?? event.error.type,
            error: ProbeErrorSignal(
                id: event.error.id,
                source: event.error.source.rawValue,
                type: event.error.type,
                category: event.error.category?.rawValue,
                handling: event.error.handling?.rawValue,
                isCrash: event.error.isCrash,
                traceID: event.dd.traceId,
                spanID: event.dd.spanId,
                parentSpanID: event.dd.parentSpanId
            )
        )
    }

    static func trace(_ event: SpanEvent, runID: String) -> ProbeSignal? {
        guard
            event.operationName == "urlsession.request",
            event.tags[ProbeRuntime.Attribute.runID] == runID,
            let url = URL(string: event.resource),
            let source = ProbeTraceOnlyURLSessionContract.sourceContext(
                from: url,
                expectedRunID: runID
            )
        else {
            return nil
        }
        return ProbeSignal(
            kind: .rumTrace,
            evidenceSource: .traceMapper,
            sourceContext: source,
            rumContext: ProbeRUMContext(
                eventDateMilliseconds: Int64(
                    (event.startTime.timeIntervalSince1970 * 1_000).rounded()
                ),
                sessionID: event.tags["_dd.session.id"],
                viewID: event.tags["_dd.view.id"],
                actionIDs: event.tags["_dd.action.id"].map { [$0] }
            ),
            name: source.phase,
            trace: ProbeTraceSignal(
                operationName: event.operationName,
                serviceName: event.serviceName,
                resourceName: event.resource,
                startTimeMilliseconds: Int64(
                    (event.startTime.timeIntervalSince1970 * 1_000).rounded()
                ),
                durationNanoseconds: Int64(
                    (event.duration * 1_000_000_000).rounded()
                ),
                isError: event.isError,
                rumSessionID: event.tags["_dd.session.id"],
                rumViewID: event.tags["_dd.view.id"],
                rumActionIDs: event.tags["_dd.action.id"].map { [$0] }
            )
        )
    }

    private static func semanticContext(
        from contextInfo: [String: Encodable]?
    ) -> ProbeSemanticContext? {
        guard
            let logicalSceneID: String = value(
                ProbeRuntime.Attribute.viewScene,
                in: contextInfo
            ),
            let screen: String = value(
                ProbeRuntime.Attribute.viewScreen,
                in: contextInfo
            )
        else {
            return nil
        }
        let nativeSceneID: String? = normalizedIdentifier(
            value(ProbeRuntime.Attribute.viewSceneSessionID, in: contextInfo)
        )
        return ProbeSemanticContext(
            logicalSceneID: logicalSceneID,
            nativeSceneID: nativeSceneID,
            screen: screen
        )
    }

    private static func sourceContext(
        from contextInfo: [String: Encodable]?
    ) -> ProbeSourceContext? {
        let logicalSceneID: String? = value(
            ProbeRuntime.Attribute.sourceScene,
            in: contextInfo
        )
        let nativeSceneID: String? = normalizedIdentifier(
            value(ProbeRuntime.Attribute.sceneSessionID, in: contextInfo)
        )
        let screen: String? = value(ProbeRuntime.Attribute.screen, in: contextInfo)
        let phase: String? = value(ProbeRuntime.Attribute.phase, in: contextInfo)
        let uptime: Double? = numericValue(
            ProbeRuntime.Attribute.uptime,
            in: contextInfo
        )
        let readerGeneration: Int? = integerValue(
            ProbeRuntime.Attribute.readerControlGeneration,
            in: contextInfo
        )

        guard
            logicalSceneID != nil
                || nativeSceneID != nil
                || screen != nil
                || phase != nil
                || uptime != nil
                || readerGeneration != nil
        else {
            return nil
        }
        return ProbeSourceContext(
            logicalSceneID: logicalSceneID,
            nativeSceneID: nativeSceneID,
            screen: screen,
            phase: phase,
            uptime: uptime,
            readerControlGeneration: readerGeneration
        )
    }

    private static func value<T>(
        _ key: String,
        in contextInfo: [String: Encodable]?
    ) -> T? {
        contextInfo?[key] as? T
    }

    private static func numericValue(
        _ key: String,
        in contextInfo: [String: Encodable]?
    ) -> Double? {
        if let value: Double = value(key, in: contextInfo) {
            return value
        }
        if let value: Int = value(key, in: contextInfo) {
            return Double(value)
        }
        if let value: Int64 = value(key, in: contextInfo) {
            return Double(value)
        }
        return nil
    }

    private static func integerValue(
        _ key: String,
        in contextInfo: [String: Encodable]?
    ) -> Int? {
        if let value: Int = value(key, in: contextInfo) {
            return value
        }
        if let value: Int64 = value(key, in: contextInfo) {
            return Int(exactly: value)
        }
        return nil
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value, value != "unresolved" else {
            return nil
        }
        return value
    }
}
