/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Describes current Datadog SDK context, so the app state information can be attached to
/// the crash report and retrieved back when the application is started again.
///
/// Note: as it gets saved along with the crash report during process interruption, it's good
/// to keep this data well-packed and as small as possible.
internal struct CrashContext: Codable {
    // MARK: - Initialization

    init(
        lastTrackingConsent: TrackingConsent,
        lastRUMViewEvent: RUMEvent<RUMViewEvent>?
    ) {
        self.codableTrackingConsent = .init(from: lastTrackingConsent)
        self.codableLastRUMViewEvent = lastRUMViewEvent.flatMap { .init(from: $0) }
    }

    // MARK: - Codable values

    private var codableTrackingConsent: CodableTrackingConsent
    private var codableLastRUMViewEvent: CodableRUMViewEvent?

    // TODO: RUMM-1049 Add Codable version of `UserInfo?`, `NetworkInfo?` and `CarrierInfo?`

    enum CodingKeys: String, CodingKey {
        case codableTrackingConsent = "ctc"
        case codableLastRUMViewEvent = "lre"
    }

    // MARK: - Setters & Getters using managed types

    var lastTrackingConsent: TrackingConsent {
        set { codableTrackingConsent = CodableTrackingConsent(from: newValue) }
        get { codableTrackingConsent.managedValue }
    }

    var lastRUMViewEvent: RUMEvent<RUMViewEvent>? {
        set { codableLastRUMViewEvent = newValue.flatMap { CodableRUMViewEvent(from: $0) } }
        get { codableLastRUMViewEvent?.managedValue }
    }
}

// MARK: - Bridging managed types to Codable representation

/// Codable representation of the public `TrackingConsent`. Uses `Int8` for optimized packing.
private enum CodableTrackingConsent: Int8, Codable {
    case granted
    case notGranted
    case pending

    init(from managedValue: TrackingConsent) {
        switch managedValue {
        case .pending: self = .pending
        case .granted: self = .granted
        case .notGranted: self = .notGranted
        }
    }

    var managedValue: TrackingConsent {
        switch self {
        case .pending: return .pending
        case .granted: return .granted
        case .notGranted: return .notGranted
        }
    }
}

private struct CodableRUMViewEvent: Codable {
    let model: RUMViewEvent
    let attributes: [String: Encodable]
    let userInfoAttributes: [String: Encodable]

    init(from managedValue: RUMEvent<RUMViewEvent>) {
        self.model = managedValue.model
        self.attributes = managedValue.attributes
        self.userInfoAttributes = managedValue.userInfoAttributes
    }

    var managedValue: RUMEvent<RUMViewEvent> {
        return .init(
            model: model,
            attributes: attributes,
            userInfoAttributes: userInfoAttributes
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case model = "mdl"
        case attributes = "att"
        case userInfoAttributes = "uia"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedAttributes = try container.decode([String: CodableValue].self, forKey: .attributes)
        let decodedUserInfoAttributes = try container.decode([String: CodableValue].self, forKey: .userInfoAttributes)

        self.model = try container.decode(RUMViewEvent.self, forKey: .model)
        self.attributes = decodedAttributes.compactMapValues { $0 }
        self.userInfoAttributes = decodedUserInfoAttributes.compactMapValues { $0 }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let encodedAttributes = attributes.mapValues { EncodableValue($0) }
        let encodedUserInfoAttributes = userInfoAttributes.mapValues { EncodableValue($0) }

        try container.encode(model, forKey: .model)
        try container.encode(encodedAttributes, forKey: .attributes)
        try container.encode(encodedUserInfoAttributes, forKey: .userInfoAttributes)
    }
}

// MARK: - Codable Helpers

/// Helper type performing type erasure of encoded JSON types.
/// It conforms to `Encodable`, so decoded value can be further serialized into exactly the same JSON representation.
private struct CodableValue: Codable {
    private let value: Encodable

    init<T: Encodable>(value: T) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            self.init(value: bool)
        } else if let uint64 = try? container.decode(UInt64.self) {
            self.init(value: uint64)
        } else if let int = try? container.decode(Int.self) {
            self.init(value: int)
        } else if let double = try? container.decode(Double.self) {
            self.init(value: double)
        } else if let string = try? container.decode(String.self) {
            self.init(value: string)
        } else if let array = try? container.decode([CodableValue].self) {
            self.init(value: array)
        } else if let dictionary = try? container.decode([String: CodableValue].self) {
            self.init(value: dictionary)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Custom attribute at \(container.codingPath) cannot is not a `Codable` type supported by the SDK."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
