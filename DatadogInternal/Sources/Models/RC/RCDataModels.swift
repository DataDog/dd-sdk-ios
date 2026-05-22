/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// This file was generated from JSON Schema. Do not modify it directly.

// swiftlint:disable all

/// RUM Browser & Mobile SDKs Remote Configuration properties
public struct RUMSdkConfig: Codable {
    /// RUM feature Remote Configuration properties
    public let rum: RUM?

    public enum CodingKeys: String, CodingKey {
        case rum = "rum"
    }

    /// RUM Browser & Mobile SDKs Remote Configuration properties
    ///
    /// - Parameters:
    ///   - rum: RUM feature Remote Configuration properties
    public init(
        rum: RUM? = nil
    ) {
        self.rum = rum
    }

    /// RUM feature Remote Configuration properties
    public struct RUM: Codable {
        /// URLs where tracing is allowed
        public let allowedTracingUrls: [AllowedTracingUrls]?

        /// Origins where tracking is allowed
        public let allowedTrackingOrigins: [AllowedTrackingOrigins]?

        /// UUID of the application
        public let applicationId: String

        /// Function to define global context
        public let context: [Context]?

        /// Session replay default privacy level
        public let defaultPrivacyLevel: String?

        /// Privacy control for action name
        public let enablePrivacyForActionName: Bool?

        /// The environment for this application
        public let env: String?

        /// The service name for this application
        public let service: String?

        /// The percentage of sessions with RUM & Session Replay pricing tracked
        public let sessionReplaySampleRate: Double?

        /// The percentage of sessions tracked
        public let sessionSampleRate: Double?

        /// The percentage of traces sampled
        public let traceSampleRate: Double?

        /// Whether to track sessions across subdomains
        public let trackSessionAcrossSubdomains: Bool?

        /// Function to define user information
        public let user: [User]?

        /// The version for this application
        public let version: Version?

        public enum CodingKeys: String, CodingKey {
            case allowedTracingUrls = "allowedTracingUrls"
            case allowedTrackingOrigins = "allowedTrackingOrigins"
            case applicationId = "applicationId"
            case context = "context"
            case defaultPrivacyLevel = "defaultPrivacyLevel"
            case enablePrivacyForActionName = "enablePrivacyForActionName"
            case env = "env"
            case service = "service"
            case sessionReplaySampleRate = "sessionReplaySampleRate"
            case sessionSampleRate = "sessionSampleRate"
            case traceSampleRate = "traceSampleRate"
            case trackSessionAcrossSubdomains = "trackSessionAcrossSubdomains"
            case user = "user"
            case version = "version"
        }

        /// RUM feature Remote Configuration properties
        ///
        /// - Parameters:
        ///   - allowedTracingUrls: URLs where tracing is allowed
        ///   - allowedTrackingOrigins: Origins where tracking is allowed
        ///   - applicationId: UUID of the application
        ///   - context: Function to define global context
        ///   - defaultPrivacyLevel: Session replay default privacy level
        ///   - enablePrivacyForActionName: Privacy control for action name
        ///   - env: The environment for this application
        ///   - service: The service name for this application
        ///   - sessionReplaySampleRate: The percentage of sessions with RUM & Session Replay pricing tracked
        ///   - sessionSampleRate: The percentage of sessions tracked
        ///   - traceSampleRate: The percentage of traces sampled
        ///   - trackSessionAcrossSubdomains: Whether to track sessions across subdomains
        ///   - user: Function to define user information
        ///   - version: The version for this application
        public init(
            allowedTracingUrls: [AllowedTracingUrls]? = nil,
            allowedTrackingOrigins: [AllowedTrackingOrigins]? = nil,
            applicationId: String,
            context: [Context]? = nil,
            defaultPrivacyLevel: String? = nil,
            enablePrivacyForActionName: Bool? = nil,
            env: String? = nil,
            service: String? = nil,
            sessionReplaySampleRate: Double? = nil,
            sessionSampleRate: Double? = nil,
            traceSampleRate: Double? = nil,
            trackSessionAcrossSubdomains: Bool? = nil,
            user: [User]? = nil,
            version: Version? = nil
        ) {
            self.allowedTracingUrls = allowedTracingUrls
            self.allowedTrackingOrigins = allowedTrackingOrigins
            self.applicationId = applicationId
            self.context = context
            self.defaultPrivacyLevel = defaultPrivacyLevel
            self.enablePrivacyForActionName = enablePrivacyForActionName
            self.env = env
            self.service = service
            self.sessionReplaySampleRate = sessionReplaySampleRate
            self.sessionSampleRate = sessionSampleRate
            self.traceSampleRate = traceSampleRate
            self.trackSessionAcrossSubdomains = trackSessionAcrossSubdomains
            self.user = user
            self.version = version
        }

        public struct AllowedTracingUrls: Codable {
            public let match: Match

            /// List of propagator types
            public let propagatorTypes: [PropagatorTypes]?

            public enum CodingKeys: String, CodingKey {
                case match = "match"
                case propagatorTypes = "propagatorTypes"
            }

            ///
            /// - Parameters:
            ///   - match:
            ///   - propagatorTypes: List of propagator types
            public init(
                match: Match,
                propagatorTypes: [PropagatorTypes]? = nil
            ) {
                self.match = match
                self.propagatorTypes = propagatorTypes
            }

            public struct Match: Codable {
                /// Remote config serialized type of match
                public let rcSerializedType: RcSerializedType

                /// Match value
                public let value: String

                public enum CodingKeys: String, CodingKey {
                    case rcSerializedType = "rcSerializedType"
                    case value = "value"
                }

                ///
                /// - Parameters:
                ///   - rcSerializedType: Remote config serialized type of match
                ///   - value: Match value
                public init(
                    rcSerializedType: RcSerializedType,
                    value: String
                ) {
                    self.rcSerializedType = rcSerializedType
                    self.value = value
                }

                /// Remote config serialized type of match
                public enum RcSerializedType: String, Codable {
                    case string = "string"
                    case regex = "regex"
                }
            }

            public enum PropagatorTypes: String, Codable {
                case datadog = "datadog"
                case b3 = "b3"
                case b3multi = "b3multi"
                case tracecontext = "tracecontext"
            }
        }

        public struct AllowedTrackingOrigins: Codable {
            /// Remote config serialized type of match
            public let rcSerializedType: RcSerializedType

            /// Match value
            public let value: String

            public enum CodingKeys: String, CodingKey {
                case rcSerializedType = "rcSerializedType"
                case value = "value"
            }

            ///
            /// - Parameters:
            ///   - rcSerializedType: Remote config serialized type of match
            ///   - value: Match value
            public init(
                rcSerializedType: RcSerializedType,
                value: String
            ) {
                self.rcSerializedType = rcSerializedType
                self.value = value
            }

            /// Remote config serialized type of match
            public enum RcSerializedType: String, Codable {
                case string = "string"
                case regex = "regex"
            }
        }

        public struct Context: Codable {
            public let key: String

            public let value: Value

            public enum CodingKeys: String, CodingKey {
                case key = "key"
                case value = "value"
            }

            ///
            /// - Parameters:
            ///   - key:
            ///   - value:
            public init(
                key: String,
                value: Value
            ) {
                self.key = key
                self.value = value
            }

            public enum Value: Codable {
                case js(value: Js)
                case cookie(value: Cookie)
                case dom(value: Dom)
                case localStorage(value: LocalStorage)

                // MARK: - Codable

                public func encode(to encoder: Encoder) throws {
                    // Encode only the associated value, without encoding enum case
                    var container = encoder.singleValueContainer()

                    switch self {
                    case .js(let value):
                        try container.encode(value)
                    case .cookie(let value):
                        try container.encode(value)
                    case .dom(let value):
                        try container.encode(value)
                    case .localStorage(let value):
                        try container.encode(value)
                    }
                }

                public init(from decoder: Decoder) throws {
                    // Decode enum case from associated value
                    let container = try decoder.singleValueContainer()

                    if let value = try? container.decode(Js.self) {
                        self = .js(value: value)
                        return
                    }
                    if let value = try? container.decode(Cookie.self) {
                        self = .cookie(value: value)
                        return
                    }
                    if let value = try? container.decode(Dom.self) {
                        self = .dom(value: value)
                        return
                    }
                    if let value = try? container.decode(LocalStorage.self) {
                        self = .localStorage(value: value)
                        return
                    }
                    let error = DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: """
                        Failed to decode `Value`.
                        Ran out of possibilities when trying to decode the value of associated type.
                        """
                    )
                    throw DecodingError.typeMismatch(Value.self, error)
                }

                public struct Js: Codable {
                    public let extractor: Extractor?

                    public let path: String

                    public let rcSerializedType: String = "dynamic"

                    public let strategy: String = "js"

                    public enum CodingKeys: String, CodingKey {
                        case extractor = "extractor"
                        case path = "path"
                        case rcSerializedType = "rcSerializedType"
                        case strategy = "strategy"
                    }

                    ///
                    /// - Parameters:
                    ///   - extractor:
                    ///   - path:
                    public init(
                        extractor: Extractor? = nil,
                        path: String
                    ) {
                        self.extractor = extractor
                        self.path = path
                    }

                    public struct Extractor: Codable {
                        /// Remote config serialized type for regex extraction
                        public let rcSerializedType: String = "regex"

                        /// Regex pattern for value extraction
                        public let value: String

                        public enum CodingKeys: String, CodingKey {
                            case rcSerializedType = "rcSerializedType"
                            case value = "value"
                        }

                        ///
                        /// - Parameters:
                        ///   - value: Regex pattern for value extraction
                        public init(
                            value: String
                        ) {
                            self.value = value
                        }
                    }
                }

                public struct Cookie: Codable {
                    public let extractor: Extractor?

                    public let name: String

                    public let rcSerializedType: String = "dynamic"

                    public let strategy: String = "cookie"

                    public enum CodingKeys: String, CodingKey {
                        case extractor = "extractor"
                        case name = "name"
                        case rcSerializedType = "rcSerializedType"
                        case strategy = "strategy"
                    }

                    ///
                    /// - Parameters:
                    ///   - extractor:
                    ///   - name:
                    public init(
                        extractor: Extractor? = nil,
                        name: String
                    ) {
                        self.extractor = extractor
                        self.name = name
                    }

                    public struct Extractor: Codable {
                        /// Remote config serialized type for regex extraction
                        public let rcSerializedType: String = "regex"

                        /// Regex pattern for value extraction
                        public let value: String

                        public enum CodingKeys: String, CodingKey {
                            case rcSerializedType = "rcSerializedType"
                            case value = "value"
                        }

                        ///
                        /// - Parameters:
                        ///   - value: Regex pattern for value extraction
                        public init(
                            value: String
                        ) {
                            self.value = value
                        }
                    }
                }

                public struct Dom: Codable {
                    public let attribute: String?

                    public let extractor: Extractor?

                    public let rcSerializedType: String = "dynamic"

                    public let selector: String

                    public let strategy: String = "dom"

                    public enum CodingKeys: String, CodingKey {
                        case attribute = "attribute"
                        case extractor = "extractor"
                        case rcSerializedType = "rcSerializedType"
                        case selector = "selector"
                        case strategy = "strategy"
                    }

                    ///
                    /// - Parameters:
                    ///   - attribute:
                    ///   - extractor:
                    ///   - selector:
                    public init(
                        attribute: String? = nil,
                        extractor: Extractor? = nil,
                        selector: String
                    ) {
                        self.attribute = attribute
                        self.extractor = extractor
                        self.selector = selector
                    }

                    public struct Extractor: Codable {
                        /// Remote config serialized type for regex extraction
                        public let rcSerializedType: String = "regex"

                        /// Regex pattern for value extraction
                        public let value: String

                        public enum CodingKeys: String, CodingKey {
                            case rcSerializedType = "rcSerializedType"
                            case value = "value"
                        }

                        ///
                        /// - Parameters:
                        ///   - value: Regex pattern for value extraction
                        public init(
                            value: String
                        ) {
                            self.value = value
                        }
                    }
                }

                public struct LocalStorage: Codable {
                    public let extractor: Extractor?

                    public let key: String

                    public let rcSerializedType: String = "dynamic"

                    public let strategy: String = "localStorage"

                    public enum CodingKeys: String, CodingKey {
                        case extractor = "extractor"
                        case key = "key"
                        case rcSerializedType = "rcSerializedType"
                        case strategy = "strategy"
                    }

                    ///
                    /// - Parameters:
                    ///   - extractor:
                    ///   - key:
                    public init(
                        extractor: Extractor? = nil,
                        key: String
                    ) {
                        self.extractor = extractor
                        self.key = key
                    }

                    public struct Extractor: Codable {
                        /// Remote config serialized type for regex extraction
                        public let rcSerializedType: String = "regex"

                        /// Regex pattern for value extraction
                        public let value: String

                        public enum CodingKeys: String, CodingKey {
                            case rcSerializedType = "rcSerializedType"
                            case value = "value"
                        }

                        ///
                        /// - Parameters:
                        ///   - value: Regex pattern for value extraction
                        public init(
                            value: String
                        ) {
                            self.value = value
                        }
                    }
                }
            }
        }

        public struct User: Codable {
            public let key: String

            public let value: Value

            public enum CodingKeys: String, CodingKey {
                case key = "key"
                case value = "value"
            }

            ///
            /// - Parameters:
            ///   - key:
            ///   - value:
            public init(
                key: String,
                value: Value
            ) {
                self.key = key
                self.value = value
            }

            public enum Value: Codable {
                case js(value: Js)
                case cookie(value: Cookie)
                case dom(value: Dom)
                case localStorage(value: LocalStorage)

                // MARK: - Codable

                public func encode(to encoder: Encoder) throws {
                    // Encode only the associated value, without encoding enum case
                    var container = encoder.singleValueContainer()

                    switch self {
                    case .js(let value):
                        try container.encode(value)
                    case .cookie(let value):
                        try container.encode(value)
                    case .dom(let value):
                        try container.encode(value)
                    case .localStorage(let value):
                        try container.encode(value)
                    }
                }

                public init(from decoder: Decoder) throws {
                    // Decode enum case from associated value
                    let container = try decoder.singleValueContainer()

                    if let value = try? container.decode(Js.self) {
                        self = .js(value: value)
                        return
                    }
                    if let value = try? container.decode(Cookie.self) {
                        self = .cookie(value: value)
                        return
                    }
                    if let value = try? container.decode(Dom.self) {
                        self = .dom(value: value)
                        return
                    }
                    if let value = try? container.decode(LocalStorage.self) {
                        self = .localStorage(value: value)
                        return
                    }
                    let error = DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: """
                        Failed to decode `Value`.
                        Ran out of possibilities when trying to decode the value of associated type.
                        """
                    )
                    throw DecodingError.typeMismatch(Value.self, error)
                }

                public struct Js: Codable {
                    public let extractor: Extractor?

                    public let path: String

                    public let rcSerializedType: String = "dynamic"

                    public let strategy: String = "js"

                    public enum CodingKeys: String, CodingKey {
                        case extractor = "extractor"
                        case path = "path"
                        case rcSerializedType = "rcSerializedType"
                        case strategy = "strategy"
                    }

                    ///
                    /// - Parameters:
                    ///   - extractor:
                    ///   - path:
                    public init(
                        extractor: Extractor? = nil,
                        path: String
                    ) {
                        self.extractor = extractor
                        self.path = path
                    }

                    public struct Extractor: Codable {
                        /// Remote config serialized type for regex extraction
                        public let rcSerializedType: String = "regex"

                        /// Regex pattern for value extraction
                        public let value: String

                        public enum CodingKeys: String, CodingKey {
                            case rcSerializedType = "rcSerializedType"
                            case value = "value"
                        }

                        ///
                        /// - Parameters:
                        ///   - value: Regex pattern for value extraction
                        public init(
                            value: String
                        ) {
                            self.value = value
                        }
                    }
                }

                public struct Cookie: Codable {
                    public let extractor: Extractor?

                    public let name: String

                    public let rcSerializedType: String = "dynamic"

                    public let strategy: String = "cookie"

                    public enum CodingKeys: String, CodingKey {
                        case extractor = "extractor"
                        case name = "name"
                        case rcSerializedType = "rcSerializedType"
                        case strategy = "strategy"
                    }

                    ///
                    /// - Parameters:
                    ///   - extractor:
                    ///   - name:
                    public init(
                        extractor: Extractor? = nil,
                        name: String
                    ) {
                        self.extractor = extractor
                        self.name = name
                    }

                    public struct Extractor: Codable {
                        /// Remote config serialized type for regex extraction
                        public let rcSerializedType: String = "regex"

                        /// Regex pattern for value extraction
                        public let value: String

                        public enum CodingKeys: String, CodingKey {
                            case rcSerializedType = "rcSerializedType"
                            case value = "value"
                        }

                        ///
                        /// - Parameters:
                        ///   - value: Regex pattern for value extraction
                        public init(
                            value: String
                        ) {
                            self.value = value
                        }
                    }
                }

                public struct Dom: Codable {
                    public let attribute: String?

                    public let extractor: Extractor?

                    public let rcSerializedType: String = "dynamic"

                    public let selector: String

                    public let strategy: String = "dom"

                    public enum CodingKeys: String, CodingKey {
                        case attribute = "attribute"
                        case extractor = "extractor"
                        case rcSerializedType = "rcSerializedType"
                        case selector = "selector"
                        case strategy = "strategy"
                    }

                    ///
                    /// - Parameters:
                    ///   - attribute:
                    ///   - extractor:
                    ///   - selector:
                    public init(
                        attribute: String? = nil,
                        extractor: Extractor? = nil,
                        selector: String
                    ) {
                        self.attribute = attribute
                        self.extractor = extractor
                        self.selector = selector
                    }

                    public struct Extractor: Codable {
                        /// Remote config serialized type for regex extraction
                        public let rcSerializedType: String = "regex"

                        /// Regex pattern for value extraction
                        public let value: String

                        public enum CodingKeys: String, CodingKey {
                            case rcSerializedType = "rcSerializedType"
                            case value = "value"
                        }

                        ///
                        /// - Parameters:
                        ///   - value: Regex pattern for value extraction
                        public init(
                            value: String
                        ) {
                            self.value = value
                        }
                    }
                }

                public struct LocalStorage: Codable {
                    public let extractor: Extractor?

                    public let key: String

                    public let rcSerializedType: String = "dynamic"

                    public let strategy: String = "localStorage"

                    public enum CodingKeys: String, CodingKey {
                        case extractor = "extractor"
                        case key = "key"
                        case rcSerializedType = "rcSerializedType"
                        case strategy = "strategy"
                    }

                    ///
                    /// - Parameters:
                    ///   - extractor:
                    ///   - key:
                    public init(
                        extractor: Extractor? = nil,
                        key: String
                    ) {
                        self.extractor = extractor
                        self.key = key
                    }

                    public struct Extractor: Codable {
                        /// Remote config serialized type for regex extraction
                        public let rcSerializedType: String = "regex"

                        /// Regex pattern for value extraction
                        public let value: String

                        public enum CodingKeys: String, CodingKey {
                            case rcSerializedType = "rcSerializedType"
                            case value = "value"
                        }

                        ///
                        /// - Parameters:
                        ///   - value: Regex pattern for value extraction
                        public init(
                            value: String
                        ) {
                            self.value = value
                        }
                    }
                }
            }
        }

        /// The version for this application
        public enum Version: Codable {
            case js(value: Js)
            case cookie(value: Cookie)
            case dom(value: Dom)
            case localStorage(value: LocalStorage)

            // MARK: - Codable

            public func encode(to encoder: Encoder) throws {
                // Encode only the associated value, without encoding enum case
                var container = encoder.singleValueContainer()

                switch self {
                case .js(let value):
                    try container.encode(value)
                case .cookie(let value):
                    try container.encode(value)
                case .dom(let value):
                    try container.encode(value)
                case .localStorage(let value):
                    try container.encode(value)
                }
            }

            public init(from decoder: Decoder) throws {
                // Decode enum case from associated value
                let container = try decoder.singleValueContainer()

                if let value = try? container.decode(Js.self) {
                    self = .js(value: value)
                    return
                }
                if let value = try? container.decode(Cookie.self) {
                    self = .cookie(value: value)
                    return
                }
                if let value = try? container.decode(Dom.self) {
                    self = .dom(value: value)
                    return
                }
                if let value = try? container.decode(LocalStorage.self) {
                    self = .localStorage(value: value)
                    return
                }
                let error = DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: """
                    Failed to decode `Version`.
                    Ran out of possibilities when trying to decode the value of associated type.
                    """
                )
                throw DecodingError.typeMismatch(Version.self, error)
            }

            public struct Js: Codable {
                public let extractor: Extractor?

                public let path: String

                public let rcSerializedType: String = "dynamic"

                public let strategy: String = "js"

                public enum CodingKeys: String, CodingKey {
                    case extractor = "extractor"
                    case path = "path"
                    case rcSerializedType = "rcSerializedType"
                    case strategy = "strategy"
                }

                ///
                /// - Parameters:
                ///   - extractor:
                ///   - path:
                public init(
                    extractor: Extractor? = nil,
                    path: String
                ) {
                    self.extractor = extractor
                    self.path = path
                }

                public struct Extractor: Codable {
                    /// Remote config serialized type for regex extraction
                    public let rcSerializedType: String = "regex"

                    /// Regex pattern for value extraction
                    public let value: String

                    public enum CodingKeys: String, CodingKey {
                        case rcSerializedType = "rcSerializedType"
                        case value = "value"
                    }

                    ///
                    /// - Parameters:
                    ///   - value: Regex pattern for value extraction
                    public init(
                        value: String
                    ) {
                        self.value = value
                    }
                }
            }

            public struct Cookie: Codable {
                public let extractor: Extractor?

                public let name: String

                public let rcSerializedType: String = "dynamic"

                public let strategy: String = "cookie"

                public enum CodingKeys: String, CodingKey {
                    case extractor = "extractor"
                    case name = "name"
                    case rcSerializedType = "rcSerializedType"
                    case strategy = "strategy"
                }

                ///
                /// - Parameters:
                ///   - extractor:
                ///   - name:
                public init(
                    extractor: Extractor? = nil,
                    name: String
                ) {
                    self.extractor = extractor
                    self.name = name
                }

                public struct Extractor: Codable {
                    /// Remote config serialized type for regex extraction
                    public let rcSerializedType: String = "regex"

                    /// Regex pattern for value extraction
                    public let value: String

                    public enum CodingKeys: String, CodingKey {
                        case rcSerializedType = "rcSerializedType"
                        case value = "value"
                    }

                    ///
                    /// - Parameters:
                    ///   - value: Regex pattern for value extraction
                    public init(
                        value: String
                    ) {
                        self.value = value
                    }
                }
            }

            public struct Dom: Codable {
                public let attribute: String?

                public let extractor: Extractor?

                public let rcSerializedType: String = "dynamic"

                public let selector: String

                public let strategy: String = "dom"

                public enum CodingKeys: String, CodingKey {
                    case attribute = "attribute"
                    case extractor = "extractor"
                    case rcSerializedType = "rcSerializedType"
                    case selector = "selector"
                    case strategy = "strategy"
                }

                ///
                /// - Parameters:
                ///   - attribute:
                ///   - extractor:
                ///   - selector:
                public init(
                    attribute: String? = nil,
                    extractor: Extractor? = nil,
                    selector: String
                ) {
                    self.attribute = attribute
                    self.extractor = extractor
                    self.selector = selector
                }

                public struct Extractor: Codable {
                    /// Remote config serialized type for regex extraction
                    public let rcSerializedType: String = "regex"

                    /// Regex pattern for value extraction
                    public let value: String

                    public enum CodingKeys: String, CodingKey {
                        case rcSerializedType = "rcSerializedType"
                        case value = "value"
                    }

                    ///
                    /// - Parameters:
                    ///   - value: Regex pattern for value extraction
                    public init(
                        value: String
                    ) {
                        self.value = value
                    }
                }
            }

            public struct LocalStorage: Codable {
                public let extractor: Extractor?

                public let key: String

                public let rcSerializedType: String = "dynamic"

                public let strategy: String = "localStorage"

                public enum CodingKeys: String, CodingKey {
                    case extractor = "extractor"
                    case key = "key"
                    case rcSerializedType = "rcSerializedType"
                    case strategy = "strategy"
                }

                ///
                /// - Parameters:
                ///   - extractor:
                ///   - key:
                public init(
                    extractor: Extractor? = nil,
                    key: String
                ) {
                    self.extractor = extractor
                    self.key = key
                }

                public struct Extractor: Codable {
                    /// Remote config serialized type for regex extraction
                    public let rcSerializedType: String = "regex"

                    /// Regex pattern for value extraction
                    public let value: String

                    public enum CodingKeys: String, CodingKey {
                        case rcSerializedType = "rcSerializedType"
                        case value = "value"
                    }

                    ///
                    /// - Parameters:
                    ///   - value: Regex pattern for value extraction
                    public init(
                        value: String
                    ) {
                        self.value = value
                    }
                }
            }
        }
    }
}

// Generated from https://github.com/DataDog/dd-go/blob/0e826636c2da5ed0223e01e537c3f4b96d6e347f/remote-config/apps/rc-schema-validation/schemas/rum-sdk-config.json