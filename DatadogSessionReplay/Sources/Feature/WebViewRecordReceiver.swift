/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal)
import DatadogInternal

internal final class WebViewRecordReceiver: FeatureMessageReceiver, @unchecked Sendable {
    internal struct WebRecord: Encodable {
        /// The RUM application ID of all records.
        let applicationID: String
        /// The RUM session ID of all records.
        let sessionID: String
        /// The RUM view ID of all records.
        let viewID: String
        /// Records enriched with further information.
        let records: [AnyEncodable]
    }

    // Expired receipts can arrive in either order. Pending records are only held briefly, with a
    // shared byte budget, while the matching Browser view is admitted by RUM.
    private struct Pending {
        let key: RUMWebViewReplayRenewal.Key
        let viewID: String
        let event: Data
        let consentRevision: UInt64
        let receivedAt: TimeInterval
    }

    private struct Accepted {
        let receipt: RUMWebViewReplayRenewal
        let receivedAt: TimeInterval
    }

    private struct RenewalState {
        static let retention: TimeInterval = 10
        static let maxEntries = 32
        var generation: UInt64 = 0
        var pending: [Pending] = []
        var accepted: [Accepted] = []
        var pendingExpiryScheduled = false

        mutating func discardExpired(at now: TimeInterval, consentRevision: UInt64) {
            pending.removeAll {
                !$0.key.owner.isValid || $0.consentRevision != consentRevision || now - $0.receivedAt >= Self.retention
            }
            accepted.removeAll {
                !$0.receipt.key.owner.isValid || $0.receipt.consentRevision != consentRevision || now - $0.receivedAt >= Self.retention
            }
        }
    }

    /// Session Replay feature scope.
    let scope: FeatureScope
    private let clock = SystemMonotonicClock()
    @ReadWriteLock
    private var renewalState = RenewalState()

    init(scope: FeatureScope) {
        self.scope = scope
    }

    func clearAllData() {
        _renewalState.mutate { state in
            state.generation &+= 1
            state.pending.removeAll()
            state.accepted.removeAll()
        }
    }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        let record: WebViewMessage
        let receipt: WebViewMessageWithRUMContext?
        let legacyRegistration: RUMLegacyWebViewTrackingReceipt?
        switch message {
        case let .context(context):
            if context.trackingConsent != .granted {
                clearAllData()
            }
            return false
        case let .payload(renewal as RUMWebViewReplayRenewal):
            accept(renewal, in: core)
            return true
        case let .webview(message):
            record = message
            receipt = nil
            legacyRegistration = nil
        case let .payload(message as WebViewMessageWithRUMContext):
            record = message.message
            receipt = message
            legacyRegistration = nil
        case let .payload(message as WebViewMessageWithLegacyRUMRegistration):
            record = message.message
            receipt = nil
            legacyRegistration = message.receipt
        default:
            return false
        }
        guard case let .record(event, view) = record else {
            return false
        }

        let key = receipt?.replayRenewalKey(forBrowserViewID: view.id)
        let generation = key.map { _ in renewalState.generation }
        scope.eventWriteContext { context, writer in
            guard legacyRegistration?.isCurrent != false else {
                return
            }
            let current = context.additionalContext(ofType: RUMCoreContext.self)
            let rumContext: RUMCoreContext?
            if let receipt {
                rumContext = receipt.rumContext(in: core, sessionID: current?.sessionID)
            } else {
                rumContext = current
            }
            if let rumContext, rumContext.sessionSampler.isSampled {
                let webViewContext = context.additionalContext(ofType: RUMWebViewContext.self)
                self.write(event, viewID: view.id, context: rumContext, offset: webViewContext?.serverTimeOffset(forView: view.id), writer: writer)
            } else if let key, let generation, context.trackingConsent == .granted {
                self.receiveExpired(
                    event,
                    viewID: view.id,
                    key: key,
                    generation: generation,
                    consentRevision: context.trackingConsentRevision,
                    core: core,
                    writer: writer
                )
            }
        }

        return true
    }

    private func receiveExpired(
        _ event: WebViewMessage.Event,
        viewID: String,
        key: RUMWebViewReplayRenewal.Key,
        generation: UInt64,
        consentRevision: UInt64,
        core: DatadogCoreProtocol,
        writer: Writer
    ) {
        guard key.owner.isValid, RUMContextHandoff.owner(in: core) === key.owner else {
            return
        }
        let now = self.clock.elapsedTime
        var shouldRemovePending = false
        _renewalState.mutate { state in
            guard generation == state.generation else {
                return
            }
            state.discardExpired(at: now, consentRevision: consentRevision)
            if let accepted = state.accepted.last(where: { $0.receipt.key == key }) {
                if isLive(accepted.receipt, in: core) {
                    write(event, viewID: viewID, context: accepted.receipt.context, offset: accepted.receipt.offset, writer: writer)
                }
                return
            }
            guard state.pending.count < RenewalState.maxEntries, let encoded = try? JSONSerialization.data(withJSONObject: event),
                  encoded.count + state.pending.reduce(0, { $0 + $1.event.count }) <= Int(SessionReplay.maxObjectSize) else {
                return
            }
            state.pending.append(.init(key: key, viewID: viewID, event: encoded, consentRevision: consentRevision, receivedAt: now))
            guard !state.pendingExpiryScheduled else {
                return
            }
            state.pendingExpiryScheduled = true
            shouldRemovePending = true
        }
        if shouldRemovePending {
            schedulePendingRemoval(after: RenewalState.retention)
        }
    }

    private func schedulePendingRemoval(after delay: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                return
            }
            let now = self.clock.elapsedTime
            var remaining: TimeInterval?
            self._renewalState.mutate { state in
                state.pending.removeAll { !$0.key.owner.isValid || now - $0.receivedAt >= RenewalState.retention }
                guard let oldest = state.pending.first else {
                    state.pendingExpiryScheduled = false
                    return
                }
                remaining = RenewalState.retention - (now - oldest.receivedAt)
            }
            if let remaining {
                self.schedulePendingRemoval(after: remaining)
            }
        }
    }

    private func accept(_ receipt: RUMWebViewReplayRenewal, in core: DatadogCoreProtocol) {
        let generation = renewalState.generation
        scope.eventWriteContext { context, writer in
            guard context.trackingConsent == .granted, receipt.consentRevision == context.trackingConsentRevision,
                  self.isLive(receipt, in: core) else {
                return
            }
            let now = self.clock.elapsedTime
            self._renewalState.mutate { state in
                guard generation == state.generation else {
                    return
                }
                state.discardExpired(at: now, consentRevision: receipt.consentRevision)
                let matches = state.pending.filter { $0.key == receipt.key }
                state.pending.removeAll { $0.key == receipt.key }
                state.accepted.removeAll { $0.receipt.key == receipt.key }
                if state.accepted.count == RenewalState.maxEntries {
                    state.accepted.removeFirst()
                }
                state.accepted.append(.init(receipt: receipt, receivedAt: now))
                for match in matches {
                    if let event = try? JSONSerialization.jsonObject(with: match.event) as? WebViewMessage.Event {
                        self.write(event, viewID: match.viewID, context: receipt.context, offset: receipt.offset, writer: writer)
                    }
                }
            }
        }
    }

    private func isLive(_ receipt: RUMWebViewReplayRenewal, in core: DatadogCoreProtocol) -> Bool {
        let owner = receipt.key.owner
        guard receipt.context.sessionSampler.isSampled, owner.isValid, RUMContextHandoff.owner(in: core) === owner,
              let provider = core.feature(named: Feature.rum, type: RUMContextHandoffSessionValidating.self) else {
            return false
        }
        return provider.isRUMContextHandoffSessionActive(sessionID: receipt.context.sessionID, owner: owner)
    }

    private func write(
        _ event: WebViewMessage.Event,
        viewID: String,
        context: RUMCoreContext,
        offset: TimeInterval?,
        writer: Writer
    ) {
        var event = event
        if let timestamp = event["timestamp"] as? Int, let offset {
            let (adjusted, overflow) = Int64(timestamp).addingReportingOverflow(offset.dd.toInt64Milliseconds)
            if !overflow {
                event["timestamp"] = adjusted
            }
        }
        writer.write(value: WebRecord(
            applicationID: context.applicationID,
            sessionID: context.sessionID,
            viewID: viewID,
            records: [AnyEncodable(event)]
        ))
    }
}
