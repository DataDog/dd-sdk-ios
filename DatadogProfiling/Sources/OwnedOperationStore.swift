/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal) import DatadogInternal

#if !os(watchOS)
internal struct OwnedProfileOperation {
    let vital: Vital
    let ownership: RUMOperationOwnership
}

internal struct OwnedProfileCorrelation {
    let ownership: RUMOperationOwnership
    let generation: UUID
    let installedKeys: Set<AttributeKey>
}

/// Mutated only on the existing profiler queue.
internal final class OwnedOperationStore {
    struct Key: Hashable {
        let owner: ObjectIdentifier
        let origin: ObjectIdentifier
        let sessionID: String
        let name: String
        let operationKey: String?

        init(_ message: OwnedOperationMessage) {
            owner = ObjectIdentifier(message.ownership.origin.owner)
            origin = ObjectIdentifier(message.ownership.origin)
            sessionID = message.ownership.sessionID
            name = message.operation.name
            operationKey = message.operation.operationKey
        }
    }

    private struct Record {
        var vital: Vital
        let ownership: RUMOperationOwnership
    }

    private final class Subscription: RUMOperationCancellationReceiving {
        let callback: (RUMOperationOwnership) -> Void
        init(callback: @escaping (RUMOperationOwnership) -> Void) { self.callback = callback }
        func operationOwnershipDidRetire(_ ownership: RUMOperationOwnership) { callback(ownership) }
    }

    private struct RegisteredSubscription {
        let ownership: RUMOperationOwnership
        let subscriber: Subscription
    }

    private var records: [Key: Record] = [:]
    private var subscriptions: [ObjectIdentifier: RegisteredSubscription] = [:]
    private(set) var correlation: OwnedProfileCorrelation?
    private let onRetirement: (RUMOperationOwnership) -> Void

    init(onRetirement: @escaping (RUMOperationOwnership) -> Void) {
        self.onRetirement = onRetirement
    }

    /// Subscribes before mutation and then rechecks the original admission.
    func prepare(_ ownership: RUMOperationOwnership) -> Bool {
        guard ownership.isValid else { return false }
        let identity = ObjectIdentifier(ownership)
        if subscriptions[identity] == nil {
            let subscriber = Subscription(callback: onRetirement)
            // Retain the weakly registered subscriber until all records/stamp are removed.
            subscriptions[identity] = RegisteredSubscription(ownership: ownership, subscriber: subscriber)
            guard ownership.subscribe(subscriber) else {
                subscriptions.removeValue(forKey: identity)
                return false
            }
        }
        return ownership.isValid
    }

    func installCorrelation(from message: OwnedOperationMessage) {
        correlation = OwnedProfileCorrelation(ownership: message.ownership, generation: UUID(),
                                               installedKeys: Set(message.attributes.keys))
        removeUnusedSubscriptions()
    }

    func didAssignLegacyAttributes() {
        correlation = nil
        removeUnusedSubscriptions()
    }

    /// One profiler-queue operation: filter exact installed keys before forgetting provenance.
    func retire(_ ownership: RUMOperationOwnership, attributes: inout [AttributeKey: AttributeValue]) {
        records = records.filter { $0.value.ownership !== ownership }
        if let stamp = correlation, stamp.ownership === ownership {
            removeCorrelation(stamp, attributes: &attributes)
        }
        removeUnusedSubscriptions()
    }

    func invalidateCorrelation(attributes: inout [AttributeKey: AttributeValue]) {
        if let stamp = correlation { removeCorrelation(stamp, attributes: &attributes) }
        removeUnusedSubscriptions()
    }

    func pruneInvalid(attributes: inout [AttributeKey: AttributeValue]) {
        records = records.filter { $0.value.ownership.isValid }
        if let stamp = correlation, !stamp.ownership.isValid {
            removeCorrelation(stamp, attributes: &attributes)
        }
        removeUnusedSubscriptions()
    }

    private func removeCorrelation(_ stamp: OwnedProfileCorrelation, attributes: inout [AttributeKey: AttributeValue]) {
        guard let current = correlation, current.ownership === stamp.ownership,
              current.generation == stamp.generation else { return }
        for key in stamp.installedKeys { attributes.removeValue(forKey: key) }
        correlation = nil
    }

    func start(_ message: OwnedOperationMessage) {
        records[Key(message)] = Record(vital: message.operation, ownership: message.ownership)
    }

    @discardableResult
    func end(_ message: OwnedOperationMessage) -> Bool {
        let key = Key(message)
        guard var record = records[key], record.ownership === message.ownership,
              record.ownership.isValid else { return false }
        record.vital.duration = message.operation.date.timeIntervalSince(record.vital.date).dd.toInt64Nanoseconds
        records[key] = record
        return true
    }

    var values: [Vital] { records.values.map { $0.vital } }
    var profileOperations: [OwnedProfileOperation] {
        records.values.map { OwnedProfileOperation(vital: $0.vital, ownership: $0.ownership) }
    }
    var hasOngoing: Bool { records.values.contains { $0.vital.stepType == .start && $0.vital.duration == nil } }
    var hasCompleted: Bool { records.values.contains { $0.vital.stepType == .start && $0.vital.duration != nil } }
    var hasStarts: Bool { records.values.contains { $0.vital.stepType == .start } }
    var isEmpty: Bool { records.isEmpty }

    func canExtend(at date: Date, cutOff: TimeInterval) -> Bool {
        records.values.contains {
            $0.vital.stepType == .start && $0.vital.duration == nil
                && date.timeIntervalSince($0.vital.date) < cutOff
        }
    }

    func removeRecords(preservingOngoing: Bool) {
        if preservingOngoing {
            records = records.filter { $0.value.vital.stepType == .start && $0.value.vital.duration == nil }
        } else {
            records.removeAll()
        }
        removeUnusedSubscriptions()
    }

    private func removeUnusedSubscriptions() {
        let retained = Set(records.values.map { ObjectIdentifier($0.ownership) })
        let stampID = correlation.map { ObjectIdentifier($0.ownership) }
        let removed = subscriptions.filter { !retained.contains($0.key) && stampID != $0.key }
        for (identity, registration) in removed {
            registration.ownership.unsubscribe(registration.subscriber)
            subscriptions.removeValue(forKey: identity)
        }
    }

    deinit {
        subscriptions.values.forEach { $0.ownership.unsubscribe($0.subscriber) }
    }
}
#endif
