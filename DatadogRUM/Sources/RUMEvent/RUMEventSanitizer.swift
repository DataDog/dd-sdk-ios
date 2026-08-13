/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Constraint on RUM event types that require sanitization before encoding.
internal protocol RUMSanitizableEvent {
    /// Mutable user property.
    var usr: RUMUser? { get set }

    var account: RUMAccount? { get set }

    /// Mutable event context.
    var context: RUMEventAttributes? { get set }
}

/// Sanitizes `RUMEvent` representation received from the user, so it can match Datadog RUM Events constraints.
internal struct RUMEventSanitizer {
    /// Bounds JSON buffer growth from inspectable custom attributes to the maximum RUM event size.
    static let maxTotalAttributeBytes = 1.MB

    private struct Limits {
        var remainingCount = AttributesSanitizer.Constraints.maxNumberOfAttributes
        var remainingAttributeBytes = maxTotalAttributeBytes
        var numberOfSizeLimitedAttributes = 0
    }

    private let attributesSanitizer = AttributesSanitizer(featureName: "RUM Event")

    func sanitize<Event>(event: Event) -> Event where Event: RUMSanitizableEvent {
        var event = event

        // Limit the total number and estimated content size of attributes. User and account information take
        // precedence over event context, matching the existing attribute-count policy.
        var limits = Limits()
        event.usr = sanitize(event.usr, attributesAt: \.usrInfo, limits: &limits)
        event.account = sanitize(event.account, attributesAt: \.accountInfo, limits: &limits)
        event.context = sanitize(event.context, attributesAt: \.contextInfo, limits: &limits)

        if limits.numberOfSizeLimitedAttributes > 0 {
            DD.logger.warn(
                """
                Size of RUM Event attributes exceeds the limit of \(Self.maxTotalAttributeBytes) bytes.
                \(limits.numberOfSizeLimitedAttributes) attribute(s) will be ignored.
                """
            )
        }

        return event
    }

    private func sanitize<Container>(
        _ container: Container?,
        attributesAt keyPath: WritableKeyPath<Container, [String: Encodable]>,
        limits: inout Limits
    ) -> Container? {
        guard var container else {
            return nil
        }

        container[keyPath: keyPath] = sanitize(
            attributes: container[keyPath: keyPath],
            limits: &limits
        )
        return container
    }

    private func sanitize(
        attributes: [String: Encodable],
        limits: inout Limits
    ) -> [String: Encodable] {
        let sanitizedKeys = attributesSanitizer.sanitizeKeys(for: attributes, prefixLevels: 1)
        let countLimited = attributesSanitizer.limitNumberOf(
            attributes: sanitizedKeys,
            to: limits.remainingCount
        )
        let sizeLimited = JSONAttributeSizeLimiter.limit(
            attributes: countLimited,
            remainingBytes: &limits.remainingAttributeBytes
        )

        limits.remainingCount -= sizeLimited.attributes.count
        limits.numberOfSizeLimitedAttributes += sizeLimited.numberOfRejectedAttributes
        return sizeLimited.attributes
    }
}

/// Limits Foundation-compatible attributes without invoking customer `Encodable` implementations.
private enum JSONAttributeSizeLimiter {
    private static let maxNestingDepth = 10

    struct Result {
        let attributes: [String: Encodable]
        let numberOfRejectedAttributes: Int
    }

    private struct Candidate {
        let jsonObject: Any
        let requiresSnapshot: Bool
    }

    private struct Inspection {
        var remainingBytes: Int
        var containsMutableValue = false

        mutating func consume(_ bytes: Int) -> Bool {
            guard bytes >= 0, bytes <= remainingBytes else {
                return false
            }
            remainingBytes -= bytes
            return true
        }
    }

    private enum Preparation {
        case candidate(Candidate)
        case rejected
    }

    private enum JSONValueInspection {
        case measurable
        case unsupported
        case limitExceeded
    }

    private enum Serialization {
        case written(numberOfBytes: Int, snapshot: [String: Any]?)
        case limitExceeded
        case failed
    }

    static func limit(
        attributes: [String: Encodable],
        remainingBytes: inout Int
    ) -> Result {
        guard !attributes.isEmpty else {
            return Result(attributes: attributes, numberOfRejectedAttributes: 0)
        }

        var accepted = attributes
        var candidates: [String: Candidate] = [:]
        var jsonObject: [String: Any] = [:]
        var lowerBoundRemainingBytes = remainingBytes
        var numberOfRejectedAttributes = 0

        for (key, value) in attributes {
            var inspection = Inspection(remainingBytes: lowerBoundRemainingBytes)
            guard inspection.consume(key.utf8.count) else {
                accepted.removeValue(forKey: key)
                numberOfRejectedAttributes += 1
                continue
            }

            switch prepare(value, inspection: &inspection) {
            case let .candidate(candidate):
                lowerBoundRemainingBytes = inspection.remainingBytes
                candidates[key] = candidate
                jsonObject[key] = candidate.jsonObject
            case .rejected:
                accepted.removeValue(forKey: key)
                numberOfRejectedAttributes += 1
            }
        }

        if !JSONSerialization.isValidJSONObject(jsonObject) {
            // Partition Foundation-incompatible values without executing arbitrary `Encodable` implementations.
            // These values remain in the event, but are intentionally left unverified.
            for (key, candidate) in candidates where !JSONSerialization.isValidJSONObject([key: candidate.jsonObject]) {
                candidates.removeValue(forKey: key)
                jsonObject.removeValue(forKey: key)
            }
        }

        guard !jsonObject.isEmpty else {
            return Result(
                attributes: accepted,
                numberOfRejectedAttributes: numberOfRejectedAttributes
            )
        }

        let requiresSnapshot = candidates.values.contains { $0.requiresSnapshot }
        switch serialize(
            jsonObject,
            byteLimit: remainingBytes,
            capturesSnapshot: requiresSnapshot
        ) {
        case let .written(numberOfBytes, snapshot):
            remainingBytes -= numberOfBytes
            applySnapshot(snapshot, for: candidates, to: &accepted)

        case .limitExceeded:
            // The uncommon oversized path measures attributes independently so only attributes crossing the
            // remaining budget are rejected. The normal path above performs a single Foundation serialization.
            for (key, _) in attributes {
                guard let candidate = candidates[key] else {
                    continue
                }

                switch serialize(
                    [key: candidate.jsonObject],
                    byteLimit: remainingBytes,
                    capturesSnapshot: candidate.requiresSnapshot
                ) {
                case let .written(numberOfBytes, snapshot):
                    remainingBytes -= numberOfBytes
                    if let value = snapshot?[key] {
                        accepted[key] = AnyEncodable(value)
                    }
                case .limitExceeded:
                    accepted.removeValue(forKey: key)
                    numberOfRejectedAttributes += 1
                case .failed:
                    break
                }
            }

        case .failed:
            // Preserve existing behavior if Foundation rejects a value we expected it to support.
            break
        }

        return Result(
            attributes: accepted,
            numberOfRejectedAttributes: numberOfRejectedAttributes
        )
    }

    private static func prepare(_ value: Any, inspection: inout Inspection) -> Preparation {
        let value = unwrap(value)
        switch inspectJSONValue(value, depth: 0, inspection: &inspection) {
        case .measurable:
            let jsonObject: Any = value is Void ? NSNull() : value
            return .candidate(
                Candidate(
                    jsonObject: jsonObject,
                    requiresSnapshot: inspection.containsMutableValue
                )
            )

        case .unsupported:
            if value is NSNumber || value is [Any?] || value is [String: Any?] {
                // Reject invalid numbers and native collections containing unsupported values. Measuring either
                // would require reproducing `JSONEncoder` or executing customer `Encodable` implementations.
                return .rejected
            }
            return .candidate(
                Candidate(
                    jsonObject: value,
                    requiresSnapshot: inspection.containsMutableValue
                )
            )

        case .limitExceeded:
            return .rejected
        }
    }

    private static func unwrap(_ value: Any) -> Any {
        if let value = value as? AnyEncodable {
            return unwrap(value.value)
        }
        if let value = value as? AnyCodable {
            return unwrap(value.value)
        }
        if let optional = value as? JSONOptional {
            return optional.jsonValue.map(unwrap) ?? NSNull()
        }
        return value
    }

    /// Applies allocation-safe lower bounds while inspecting a Foundation-compatible JSON value.
    private static func inspectJSONValue(
        _ value: Any,
        depth: Int,
        inspection: inout Inspection
    ) -> JSONValueInspection {
        if let optional = value as? JSONOptional {
            return inspectJSONValue(
                optional.jsonValue ?? NSNull(),
                depth: depth,
                inspection: &inspection
            )
        }

        let isFoundationObject = Swift.type(of: value) is NSObject.Type
        if isFoundationObject,
           value is NSMutableString || value is NSMutableData
            || value is NSMutableArray || value is NSMutableDictionary {
            inspection.containsMutableValue = true
        }

        switch value {
        case is Void, is NSNull:
            return .measurable
        case let value as String:
            return inspection.consume(value.utf8.count) ? .measurable : .limitExceeded
        case let values as [Any?]:
            guard depth < maxNestingDepth, inspection.consume(values.count) else {
                return .limitExceeded
            }
            for value in values {
                switch inspectJSONValue(value as Any, depth: depth + 1, inspection: &inspection) {
                case .measurable:
                    continue
                case .unsupported:
                    return .unsupported
                case .limitExceeded:
                    return .limitExceeded
                }
            }
            return .measurable
        case let values as [String: Any?]:
            guard depth < maxNestingDepth, inspection.consume(values.count) else {
                return .limitExceeded
            }
            for (key, value) in values {
                guard inspection.consume(key.utf8.count) else {
                    return .limitExceeded
                }
                switch inspectJSONValue(value as Any, depth: depth + 1, inspection: &inspection) {
                case .measurable:
                    continue
                case .unsupported:
                    return .unsupported
                case .limitExceeded:
                    return .limitExceeded
                }
            }
            return .measurable
        case let value as NSNumber:
            return value.doubleValue.isFinite ? .measurable : .unsupported
        default:
            return .unsupported
        }
    }

    private static func applySnapshot(
        _ snapshot: [String: Any]?,
        for candidates: [String: Candidate],
        to attributes: inout [String: Encodable]
    ) {
        guard let snapshot else {
            return
        }
        for (key, candidate) in candidates where candidate.requiresSnapshot {
            if let value = snapshot[key] {
                attributes[key] = AnyEncodable(value)
            }
        }
    }

    private static func serialize(
        _ jsonObject: Any,
        byteLimit: Int,
        capturesSnapshot: Bool
    ) -> Serialization {
        let stream = ByteLimitOutputStream(
            byteLimit: byteLimit,
            capturesBytes: capturesSnapshot
        )
        stream.open()
        defer { stream.close() }

        var error: NSError?
        let numberOfBytes = JSONSerialization.writeJSONObject(
            jsonObject,
            to: stream,
            options: [],
            error: &error
        )

        if stream.didExceedLimit {
            return .limitExceeded
        }
        guard error == nil, numberOfBytes >= 0 else {
            return .failed
        }
        let snapshot = stream.capturedData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        return .written(numberOfBytes: stream.numberOfBytesWritten, snapshot: snapshot)
    }
}

/// Discards serialized bytes and rejects a write before it crosses the configured limit.
private final class ByteLimitOutputStream: OutputStream {
    private let byteLimit: Int
    private var status: Stream.Status = .notOpen
    private var data: Data?

    private(set) var numberOfBytesWritten = 0
    private(set) var didExceedLimit = false

    var capturedData: Data? { data }

    init(byteLimit: Int, capturesBytes: Bool) {
        self.byteLimit = max(0, byteLimit)
        if capturesBytes {
            var data = Data()
            data.reserveCapacity(min(byteLimit, 4 * 1_024))
            self.data = data
        }
        super.init(toMemory: ())
    }

    override var hasSpaceAvailable: Bool {
        status == .open && numberOfBytesWritten < byteLimit
    }

    override var streamStatus: Stream.Status { status }

    override var streamError: Error? {
        didExceedLimit
            ? NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteOutOfSpace.rawValue)
            : nil
    }

    override func open() {
        status = .open
    }

    override func close() {
        status = .closed
    }

    override func write(_ buffer: UnsafePointer<UInt8>, maxLength length: Int) -> Int {
        guard status == .open else {
            return -1
        }
        guard length <= byteLimit - numberOfBytesWritten else {
            didExceedLimit = true
            status = .error
            return -1
        }

        data?.append(buffer, count: length)
        numberOfBytesWritten += length
        return length
    }
}

private protocol JSONOptional {
    var jsonValue: Any? { get }
}

extension Optional: JSONOptional {
    fileprivate var jsonValue: Any? { self }
}

extension RUMViewEvent: RUMSanitizableEvent {}

extension RUMActionEvent: RUMSanitizableEvent {}

extension RUMResourceEvent: RUMSanitizableEvent {}

extension RUMErrorEvent: RUMSanitizableEvent {}

extension RUMLongTaskEvent: RUMSanitizableEvent {}

extension RUMVitalAppLaunchEvent: RUMSanitizableEvent {}

extension RUMVitalOperationStepEvent: RUMSanitizableEvent {}

extension RUMTimeseriesMemoryEvent: RUMSanitizableEvent {}

extension RUMTimeseriesCpuEvent: RUMSanitizableEvent {}
