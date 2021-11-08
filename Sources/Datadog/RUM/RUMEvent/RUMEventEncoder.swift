/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `Encodable` representation of RUM event.
/// Mutable properties are subject of sanitization or data scrubbing.
/// TODO: RUMM-1584 - Remove `RUMEvent` container.
internal struct RUMEvent<DM>: Encodable where DM: RUMDataModel, DM: RUMSanitizableEvent {
    /// The actual RUM event model created by `RUMMonitor`
    var model: DM

    /// Error attributes. Only set when `DM == RUMErrorEvent` and error describes a crash.
    /// Can be entirely removed when RUMM-1463 is resolved and error values are part of the `RUMErrorEvent`.
    let errorAttributes: [String: Encodable]?

    /// Creates a RUM Event object object based on the given sanitizable model.
    ///
    /// The error attributes keys must be prefixed by `error.*`.
    ///
    /// - Parameters:
    ///   - model: The sanitizable event model.
    ///   - errorAttributes: The optional error attributes.
    init(model: DM, errorAttributes: [String: Encodable]? = nil) {
        self.model = model
        self.errorAttributes = errorAttributes
    }

    func encode(to encoder: Encoder) throws {
        // Encode attributes
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        // TODO: RUMM-1463 Remove this `errorAttributes` property once new error format is managed through `RUMDataModels`
        try errorAttributes?.forEach { attribute in
            try container.encode(CodableValue(attribute.value), forKey: DynamicCodingKey(attribute.key))
        }

        // Encode the sanitized `RUMDataModel`.
        let sanitizedModel = RUMEventSanitizer().sanitize(event: model)
        try sanitizedModel.encode(to: encoder)
    }

    /// Coding keys for dynamic `RUMEvent` attributes specified by user.
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
    }
}

/// Constraint on RUM event types that require sanitization before encoding.
internal protocol RUMSanitizableEvent {
    /// Mutable user property.
    var usr: RUMUser? { get set }

    /// Mutable event contect.
    var context: RUMEventAttributes? { get set }
}

extension RUMViewEvent: RUMSanitizableEvent {}

extension RUMActionEvent: RUMSanitizableEvent {}

extension RUMResourceEvent: RUMSanitizableEvent {}

extension RUMErrorEvent: RUMSanitizableEvent {}

extension RUMLongTaskEvent: RUMSanitizableEvent {}
