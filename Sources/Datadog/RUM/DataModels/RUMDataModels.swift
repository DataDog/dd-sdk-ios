/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

// This file was generated from JSON Schema. Do not modify it directly.

internal protocol RUMDataModel: Codable {}

/// Schema of all properties of an Action event
public struct RUMActionEvent: RUMDataModel {
    /// Internal properties
    public let dd: DD

    /// Action properties
    public var action: Action

    /// Application properties
    public let application: Application

    /// CI Visibility properties
    public let ciTest: RUMCITest?

    /// Device connectivity properties
    public let connectivity: RUMConnectivity?

    /// User provided context
    public internal(set) var context: RUMEventAttributes?

    /// Start of the event in ms from epoch
    public let date: Int64

    /// Device properties
    public let device: RUMDevice?

    /// Display properties
    public let display: RUMDisplay?

    /// Operating system properties
    public let os: RUMOperatingSystem?

    /// The service name for this application
    public let service: String?

    /// Session properties
    public let session: Session

    /// The source of this event
    public let source: Source?

    /// Synthetics properties
    public let synthetics: Synthetics?

    /// RUM event type
    public let type: String = "action"

    /// User properties
    public internal(set) var usr: RUMUser?

    /// The version for this application
    public let version: String?

    /// View properties
    public var view: View

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case action = "action"
        case application = "application"
        case ciTest = "ci_test"
        case connectivity = "connectivity"
        case context = "context"
        case date = "date"
        case device = "device"
        case display = "display"
        case os = "os"
        case service = "service"
        case session = "session"
        case source = "source"
        case synthetics = "synthetics"
        case type = "type"
        case usr = "usr"
        case version = "version"
        case view = "view"
    }

    /// Internal properties
    public struct DD: Codable {
        /// Action properties
        public let action: Action?

        /// Browser SDK version
        public let browserSdkVersion: String?

        /// Version of the RUM event format
        public let formatVersion: Int64 = 2

        /// Session-related internal properties
        public let session: Session?

        enum CodingKeys: String, CodingKey {
            case action = "action"
            case browserSdkVersion = "browser_sdk_version"
            case formatVersion = "format_version"
            case session = "session"
        }

        /// Action properties
        public struct Action: Codable {
            /// Action position properties
            public let position: Position?

            /// Target properties
            public let target: Target?

            enum CodingKeys: String, CodingKey {
                case position = "position"
                case target = "target"
            }

            /// Action position properties
            public struct Position: Codable {
                /// X coordinate relative to the target element of the action (in pixels)
                public let x: Int64

                /// Y coordinate relative to the target element of the action (in pixels)
                public let y: Int64

                enum CodingKeys: String, CodingKey {
                    case x = "x"
                    case y = "y"
                }
            }

            /// Target properties
            public struct Target: Codable {
                /// Height of the target element (in pixels)
                public let height: Int64?

                /// CSS selector path of the target element
                public let selector: String?

                /// Width of the target element (in pixels)
                public let width: Int64?

                enum CodingKeys: String, CodingKey {
                    case height = "height"
                    case selector = "selector"
                    case width = "width"
                }
            }
        }

        /// Session-related internal properties
        public struct Session: Codable {
            /// Session plan: 1 is the plan without replay, 2 is the plan with replay
            public let plan: Plan

            enum CodingKeys: String, CodingKey {
                case plan = "plan"
            }

            /// Session plan: 1 is the plan without replay, 2 is the plan with replay
            public enum Plan: Int, Codable {
                case plan1 = 1
                case plan2 = 2
            }
        }
    }

    /// Action properties
    public struct Action: Codable {
        /// Properties of the crashes of the action
        public let crash: Crash?

        /// Properties of the errors of the action
        public let error: Error?

        /// Action frustration properties
        public let frustration: Frustration?

        /// UUID of the action
        public let id: String?

        /// Duration in ns to the action is considered loaded
        public let loadingTime: Int64?

        /// Properties of the long tasks of the action
        public let longTask: LongTask?

        /// Properties of the resources of the action
        public let resource: Resource?

        /// Action target properties
        public var target: Target?

        /// Type of the action
        public let type: ActionType

        enum CodingKeys: String, CodingKey {
            case crash = "crash"
            case error = "error"
            case frustration = "frustration"
            case id = "id"
            case loadingTime = "loading_time"
            case longTask = "long_task"
            case resource = "resource"
            case target = "target"
            case type = "type"
        }

        /// Properties of the crashes of the action
        public struct Crash: Codable {
            /// Number of crashes that occurred on the action
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the errors of the action
        public struct Error: Codable {
            /// Number of errors that occurred on the action
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Action frustration properties
        public struct Frustration: Codable {
            /// Action frustration types
            public let type: [FrustrationType]

            enum CodingKeys: String, CodingKey {
                case type = "type"
            }

            public enum FrustrationType: String, Codable {
                case rageClick = "rage_click"
                case deadClick = "dead_click"
                case errorClick = "error_click"
                case rageTap = "rage_tap"
                case errorTap = "error_tap"
            }
        }

        /// Properties of the long tasks of the action
        public struct LongTask: Codable {
            /// Number of long tasks that occurred on the action
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the resources of the action
        public struct Resource: Codable {
            /// Number of resources that occurred on the action
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Action target properties
        public struct Target: Codable {
            /// Target name
            public var name: String

            enum CodingKeys: String, CodingKey {
                case name = "name"
            }
        }

        /// Type of the action
        public enum ActionType: String, Codable {
            case custom = "custom"
            case click = "click"
            case tap = "tap"
            case scroll = "scroll"
            case swipe = "swipe"
            case applicationStart = "application_start"
            case back = "back"
        }
    }

    /// Application properties
    public struct Application: Codable {
        /// UUID of the application
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Session properties
    public struct Session: Codable {
        /// Whether this session has a replay
        public let hasReplay: Bool?

        /// UUID of the session
        public let id: String

        /// Type of the session
        public let type: SessionType

        enum CodingKeys: String, CodingKey {
            case hasReplay = "has_replay"
            case id = "id"
            case type = "type"
        }

        /// Type of the session
        public enum SessionType: String, Codable {
            case user = "user"
            case synthetics = "synthetics"
            case ciTest = "ci_test"
        }
    }

    /// The source of this event
    public enum Source: String, Codable {
        case android = "android"
        case ios = "ios"
        case browser = "browser"
        case flutter = "flutter"
        case reactNative = "react-native"
        case roku = "roku"
    }

    /// Synthetics properties
    public struct Synthetics: Codable {
        /// Whether the event comes from a SDK instance injected by Synthetics
        public let injected: Bool?

        /// The identifier of the current Synthetics test results
        public let resultId: String

        /// The identifier of the current Synthetics test
        public let testId: String

        enum CodingKeys: String, CodingKey {
            case injected = "injected"
            case resultId = "result_id"
            case testId = "test_id"
        }
    }

    /// View properties
    public struct View: Codable {
        /// UUID of the view
        public let id: String

        /// Is the action starting in the foreground (focus in browser)
        public let inForeground: Bool?

        /// User defined name of the view
        public var name: String?

        /// URL that linked to the initial view of the page
        public var referrer: String?

        /// URL of the view
        public var url: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case inForeground = "in_foreground"
            case name = "name"
            case referrer = "referrer"
            case url = "url"
        }
    }
}

/// Schema of all properties of an Error event
public struct RUMErrorEvent: RUMDataModel {
    /// Internal properties
    public let dd: DD

    /// Action properties
    public let action: Action?

    /// Application properties
    public let application: Application

    /// CI Visibility properties
    public let ciTest: RUMCITest?

    /// Device connectivity properties
    public let connectivity: RUMConnectivity?

    /// User provided context
    public internal(set) var context: RUMEventAttributes?

    /// Start of the event in ms from epoch
    public let date: Int64

    /// Device properties
    public let device: RUMDevice?

    /// Display properties
    public let display: RUMDisplay?

    /// Error properties
    public var error: Error

    /// Feature flags properties
    public internal(set) var featureFlags: FeatureFlags?

    /// Operating system properties
    public let os: RUMOperatingSystem?

    /// The service name for this application
    public let service: String?

    /// Session properties
    public let session: Session

    /// The source of this event
    public let source: Source?

    /// Synthetics properties
    public let synthetics: Synthetics?

    /// RUM event type
    public let type: String = "error"

    /// User properties
    public internal(set) var usr: RUMUser?

    /// The version for this application
    public let version: String?

    /// View properties
    public var view: View

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case action = "action"
        case application = "application"
        case ciTest = "ci_test"
        case connectivity = "connectivity"
        case context = "context"
        case date = "date"
        case device = "device"
        case display = "display"
        case error = "error"
        case featureFlags = "feature_flags"
        case os = "os"
        case service = "service"
        case session = "session"
        case source = "source"
        case synthetics = "synthetics"
        case type = "type"
        case usr = "usr"
        case version = "version"
        case view = "view"
    }

    /// Internal properties
    public struct DD: Codable {
        /// Browser SDK version
        public let browserSdkVersion: String?

        /// Version of the RUM event format
        public let formatVersion: Int64 = 2

        /// Session-related internal properties
        public let session: Session?

        enum CodingKeys: String, CodingKey {
            case browserSdkVersion = "browser_sdk_version"
            case formatVersion = "format_version"
            case session = "session"
        }

        /// Session-related internal properties
        public struct Session: Codable {
            /// Session plan: 1 is the plan without replay, 2 is the plan with replay
            public let plan: Plan

            enum CodingKeys: String, CodingKey {
                case plan = "plan"
            }

            /// Session plan: 1 is the plan without replay, 2 is the plan with replay
            public enum Plan: Int, Codable {
                case plan1 = 1
                case plan2 = 2
            }
        }
    }

    /// Action properties
    public struct Action: Codable {
        /// UUID of the action
        public let id: RUMActionID

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Application properties
    public struct Application: Codable {
        /// UUID of the application
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Error properties
    public struct Error: Codable {
        /// Causes of the error
        public var causes: [Causes]?

        /// Whether the error has been handled manually in the source code or not
        public let handling: Handling?

        /// Handling call stack
        public let handlingStack: String?

        /// UUID of the error
        public let id: String?

        /// Whether this error crashed the host application
        public let isCrash: Bool?

        /// Error message
        public var message: String

        /// Resource properties of the error
        public var resource: Resource?

        /// Source of the error
        public let source: Source

        /// Source type of the error (the language or platform impacting the error stacktrace format)
        public let sourceType: SourceType?

        /// Stacktrace of the error
        public var stack: String?

        /// The type of the error
        public let type: String?

        enum CodingKeys: String, CodingKey {
            case causes = "causes"
            case handling = "handling"
            case handlingStack = "handling_stack"
            case id = "id"
            case isCrash = "is_crash"
            case message = "message"
            case resource = "resource"
            case source = "source"
            case sourceType = "source_type"
            case stack = "stack"
            case type = "type"
        }

        /// Properties for one of the error causes
        public struct Causes: Codable {
            /// Error message
            public var message: String

            /// Source of the error
            public let source: Source

            /// Stacktrace of the error
            public var stack: String?

            /// The type of the error
            public let type: String?

            enum CodingKeys: String, CodingKey {
                case message = "message"
                case source = "source"
                case stack = "stack"
                case type = "type"
            }

            /// Source of the error
            public enum Source: String, Codable {
                case network = "network"
                case source = "source"
                case console = "console"
                case logger = "logger"
                case agent = "agent"
                case webview = "webview"
                case custom = "custom"
                case report = "report"
            }
        }

        /// Whether the error has been handled manually in the source code or not
        public enum Handling: String, Codable {
            case handled = "handled"
            case unhandled = "unhandled"
        }

        /// Resource properties of the error
        public struct Resource: Codable {
            /// HTTP method of the resource
            public let method: RUMMethod

            /// The provider for this resource
            public let provider: Provider?

            /// HTTP Status code of the resource
            public let statusCode: Int64

            /// URL of the resource
            public var url: String

            enum CodingKeys: String, CodingKey {
                case method = "method"
                case provider = "provider"
                case statusCode = "status_code"
                case url = "url"
            }

            /// The provider for this resource
            public struct Provider: Codable {
                /// The domain name of the provider
                public let domain: String?

                /// The user friendly name of the provider
                public let name: String?

                /// The type of provider
                public let type: ProviderType?

                enum CodingKeys: String, CodingKey {
                    case domain = "domain"
                    case name = "name"
                    case type = "type"
                }

                /// The type of provider
                public enum ProviderType: String, Codable {
                    case ad = "ad"
                    case advertising = "advertising"
                    case analytics = "analytics"
                    case cdn = "cdn"
                    case content = "content"
                    case customerSuccess = "customer-success"
                    case firstParty = "first party"
                    case hosting = "hosting"
                    case marketing = "marketing"
                    case other = "other"
                    case social = "social"
                    case tagManager = "tag-manager"
                    case utility = "utility"
                    case video = "video"
                }
            }
        }

        /// Source of the error
        public enum Source: String, Codable {
            case network = "network"
            case source = "source"
            case console = "console"
            case logger = "logger"
            case agent = "agent"
            case webview = "webview"
            case custom = "custom"
            case report = "report"
        }

        /// Source type of the error (the language or platform impacting the error stacktrace format)
        public enum SourceType: String, Codable {
            case android = "android"
            case browser = "browser"
            case ios = "ios"
            case reactNative = "react-native"
            case flutter = "flutter"
            case roku = "roku"
        }
    }

    /// Feature flags properties
    public struct FeatureFlags: Codable {
        public internal(set) var featureFlagsInfo: [String: Encodable]
    }

    /// Session properties
    public struct Session: Codable {
        /// Whether this session has a replay
        public let hasReplay: Bool?

        /// UUID of the session
        public let id: String

        /// Type of the session
        public let type: SessionType

        enum CodingKeys: String, CodingKey {
            case hasReplay = "has_replay"
            case id = "id"
            case type = "type"
        }

        /// Type of the session
        public enum SessionType: String, Codable {
            case user = "user"
            case synthetics = "synthetics"
            case ciTest = "ci_test"
        }
    }

    /// The source of this event
    public enum Source: String, Codable {
        case android = "android"
        case ios = "ios"
        case browser = "browser"
        case flutter = "flutter"
        case reactNative = "react-native"
        case roku = "roku"
    }

    /// Synthetics properties
    public struct Synthetics: Codable {
        /// Whether the event comes from a SDK instance injected by Synthetics
        public let injected: Bool?

        /// The identifier of the current Synthetics test results
        public let resultId: String

        /// The identifier of the current Synthetics test
        public let testId: String

        enum CodingKeys: String, CodingKey {
            case injected = "injected"
            case resultId = "result_id"
            case testId = "test_id"
        }
    }

    /// View properties
    public struct View: Codable {
        /// UUID of the view
        public let id: String

        /// Is the error starting in the foreground (focus in browser)
        public let inForeground: Bool?

        /// User defined name of the view
        public var name: String?

        /// URL that linked to the initial view of the page
        public var referrer: String?

        /// URL of the view
        public var url: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case inForeground = "in_foreground"
            case name = "name"
            case referrer = "referrer"
            case url = "url"
        }
    }
}

extension RUMErrorEvent.FeatureFlags {
    public func encode(to encoder: Encoder) throws {
        // Encode dynamic properties:
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try featureFlagsInfo.forEach {
            let key = DynamicCodingKey($0)
            try dynamicContainer.encode(AnyEncodable($1), forKey: key)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode other properties into [String: Codable] dictionary:
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let dynamicKeys = dynamicContainer.allKeys
        var dictionary: [String: Codable] = [:]

        try dynamicKeys.forEach { codingKey in
            dictionary[codingKey.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: codingKey)
        }

        self.featureFlagsInfo = dictionary
    }
}

/// Schema of all properties of a Long Task event
public struct RUMLongTaskEvent: RUMDataModel {
    /// Internal properties
    public let dd: DD

    /// Action properties
    public let action: Action?

    /// Application properties
    public let application: Application

    /// CI Visibility properties
    public let ciTest: RUMCITest?

    /// Device connectivity properties
    public let connectivity: RUMConnectivity?

    /// User provided context
    public internal(set) var context: RUMEventAttributes?

    /// Start of the event in ms from epoch
    public let date: Int64

    /// Device properties
    public let device: RUMDevice?

    /// Display properties
    public let display: RUMDisplay?

    /// Long Task properties
    public let longTask: LongTask

    /// Operating system properties
    public let os: RUMOperatingSystem?

    /// The service name for this application
    public let service: String?

    /// Session properties
    public let session: Session

    /// The source of this event
    public let source: Source?

    /// Synthetics properties
    public let synthetics: Synthetics?

    /// RUM event type
    public let type: String = "long_task"

    /// User properties
    public internal(set) var usr: RUMUser?

    /// The version for this application
    public let version: String?

    /// View properties
    public var view: View

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case action = "action"
        case application = "application"
        case ciTest = "ci_test"
        case connectivity = "connectivity"
        case context = "context"
        case date = "date"
        case device = "device"
        case display = "display"
        case longTask = "long_task"
        case os = "os"
        case service = "service"
        case session = "session"
        case source = "source"
        case synthetics = "synthetics"
        case type = "type"
        case usr = "usr"
        case version = "version"
        case view = "view"
    }

    /// Internal properties
    public struct DD: Codable {
        /// Browser SDK version
        public let browserSdkVersion: String?

        /// Whether the long task should be discarded or indexed
        public let discarded: Bool?

        /// Version of the RUM event format
        public let formatVersion: Int64 = 2

        /// Session-related internal properties
        public let session: Session?

        enum CodingKeys: String, CodingKey {
            case browserSdkVersion = "browser_sdk_version"
            case discarded = "discarded"
            case formatVersion = "format_version"
            case session = "session"
        }

        /// Session-related internal properties
        public struct Session: Codable {
            /// Session plan: 1 is the plan without replay, 2 is the plan with replay
            public let plan: Plan

            enum CodingKeys: String, CodingKey {
                case plan = "plan"
            }

            /// Session plan: 1 is the plan without replay, 2 is the plan with replay
            public enum Plan: Int, Codable {
                case plan1 = 1
                case plan2 = 2
            }
        }
    }

    /// Action properties
    public struct Action: Codable {
        /// UUID of the action
        public let id: RUMActionID

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Application properties
    public struct Application: Codable {
        /// UUID of the application
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Long Task properties
    public struct LongTask: Codable {
        /// Duration in ns of the long task
        public let duration: Int64

        /// UUID of the long task
        public let id: String?

        /// Whether this long task is considered a frozen frame
        public let isFrozenFrame: Bool?

        enum CodingKeys: String, CodingKey {
            case duration = "duration"
            case id = "id"
            case isFrozenFrame = "is_frozen_frame"
        }
    }

    /// Session properties
    public struct Session: Codable {
        /// Whether this session has a replay
        public let hasReplay: Bool?

        /// UUID of the session
        public let id: String

        /// Type of the session
        public let type: SessionType

        enum CodingKeys: String, CodingKey {
            case hasReplay = "has_replay"
            case id = "id"
            case type = "type"
        }

        /// Type of the session
        public enum SessionType: String, Codable {
            case user = "user"
            case synthetics = "synthetics"
            case ciTest = "ci_test"
        }
    }

    /// The source of this event
    public enum Source: String, Codable {
        case android = "android"
        case ios = "ios"
        case browser = "browser"
        case flutter = "flutter"
        case reactNative = "react-native"
        case roku = "roku"
    }

    /// Synthetics properties
    public struct Synthetics: Codable {
        /// Whether the event comes from a SDK instance injected by Synthetics
        public let injected: Bool?

        /// The identifier of the current Synthetics test results
        public let resultId: String

        /// The identifier of the current Synthetics test
        public let testId: String

        enum CodingKeys: String, CodingKey {
            case injected = "injected"
            case resultId = "result_id"
            case testId = "test_id"
        }
    }

    /// View properties
    public struct View: Codable {
        /// UUID of the view
        public let id: String

        /// User defined name of the view
        public var name: String?

        /// URL that linked to the initial view of the page
        public var referrer: String?

        /// URL of the view
        public var url: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case name = "name"
            case referrer = "referrer"
            case url = "url"
        }
    }
}

/// Schema of all properties of a Resource event
public struct RUMResourceEvent: RUMDataModel {
    /// Internal properties
    public let dd: DD

    /// Action properties
    public let action: Action?

    /// Application properties
    public let application: Application

    /// CI Visibility properties
    public let ciTest: RUMCITest?

    /// Device connectivity properties
    public let connectivity: RUMConnectivity?

    /// User provided context
    public internal(set) var context: RUMEventAttributes?

    /// Start of the event in ms from epoch
    public let date: Int64

    /// Device properties
    public let device: RUMDevice?

    /// Display properties
    public let display: RUMDisplay?

    /// Operating system properties
    public let os: RUMOperatingSystem?

    /// Resource properties
    public var resource: Resource

    /// The service name for this application
    public let service: String?

    /// Session properties
    public let session: Session

    /// The source of this event
    public let source: Source?

    /// Synthetics properties
    public let synthetics: Synthetics?

    /// RUM event type
    public let type: String = "resource"

    /// User properties
    public internal(set) var usr: RUMUser?

    /// The version for this application
    public let version: String?

    /// View properties
    public var view: View

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case action = "action"
        case application = "application"
        case ciTest = "ci_test"
        case connectivity = "connectivity"
        case context = "context"
        case date = "date"
        case device = "device"
        case display = "display"
        case os = "os"
        case resource = "resource"
        case service = "service"
        case session = "session"
        case source = "source"
        case synthetics = "synthetics"
        case type = "type"
        case usr = "usr"
        case version = "version"
        case view = "view"
    }

    /// Internal properties
    public struct DD: Codable {
        /// Browser SDK version
        public let browserSdkVersion: String?

        /// Whether the resource should be discarded or indexed
        public let discarded: Bool?

        /// Version of the RUM event format
        public let formatVersion: Int64 = 2

        /// tracing sample rate in decimal format
        public let rulePsr: Double?

        /// Session-related internal properties
        public let session: Session?

        /// span identifier in decimal format
        public let spanId: String?

        /// trace identifier in decimal format
        public let traceId: String?

        enum CodingKeys: String, CodingKey {
            case browserSdkVersion = "browser_sdk_version"
            case discarded = "discarded"
            case formatVersion = "format_version"
            case rulePsr = "rule_psr"
            case session = "session"
            case spanId = "span_id"
            case traceId = "trace_id"
        }

        /// Session-related internal properties
        public struct Session: Codable {
            /// Session plan: 1 is the plan without replay, 2 is the plan with replay
            public let plan: Plan

            enum CodingKeys: String, CodingKey {
                case plan = "plan"
            }

            /// Session plan: 1 is the plan without replay, 2 is the plan with replay
            public enum Plan: Int, Codable {
                case plan1 = 1
                case plan2 = 2
            }
        }
    }

    /// Action properties
    public struct Action: Codable {
        /// UUID of the action
        public let id: RUMActionID

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Application properties
    public struct Application: Codable {
        /// UUID of the application
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Resource properties
    public struct Resource: Codable {
        /// Connect phase properties
        public let connect: Connect?

        /// DNS phase properties
        public let dns: DNS?

        /// Download phase properties
        public let download: Download?

        /// Duration of the resource
        public let duration: Int64

        /// First Byte phase properties
        public let firstByte: FirstByte?

        /// UUID of the resource
        public let id: String?

        /// HTTP method of the resource
        public let method: RUMMethod?

        /// The provider for this resource
        public let provider: Provider?

        /// Redirect phase properties
        public let redirect: Redirect?

        /// Size in octet of the resource response body
        public let size: Int64?

        /// SSL phase properties
        public let ssl: SSL?

        /// HTTP status code of the resource
        public let statusCode: Int64?

        /// Resource type
        public let type: ResourceType

        /// URL of the resource
        public var url: String

        enum CodingKeys: String, CodingKey {
            case connect = "connect"
            case dns = "dns"
            case download = "download"
            case duration = "duration"
            case firstByte = "first_byte"
            case id = "id"
            case method = "method"
            case provider = "provider"
            case redirect = "redirect"
            case size = "size"
            case ssl = "ssl"
            case statusCode = "status_code"
            case type = "type"
            case url = "url"
        }

        /// Connect phase properties
        public struct Connect: Codable {
            /// Duration in ns of the resource connect phase
            public let duration: Int64

            /// Duration in ns between start of the request and start of the connect phase
            public let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// DNS phase properties
        public struct DNS: Codable {
            /// Duration in ns of the resource dns phase
            public let duration: Int64

            /// Duration in ns between start of the request and start of the dns phase
            public let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// Download phase properties
        public struct Download: Codable {
            /// Duration in ns of the resource download phase
            public let duration: Int64

            /// Duration in ns between start of the request and start of the download phase
            public let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// First Byte phase properties
        public struct FirstByte: Codable {
            /// Duration in ns of the resource first byte phase
            public let duration: Int64

            /// Duration in ns between start of the request and start of the first byte phase
            public let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// The provider for this resource
        public struct Provider: Codable {
            /// The domain name of the provider
            public let domain: String?

            /// The user friendly name of the provider
            public let name: String?

            /// The type of provider
            public let type: ProviderType?

            enum CodingKeys: String, CodingKey {
                case domain = "domain"
                case name = "name"
                case type = "type"
            }

            /// The type of provider
            public enum ProviderType: String, Codable {
                case ad = "ad"
                case advertising = "advertising"
                case analytics = "analytics"
                case cdn = "cdn"
                case content = "content"
                case customerSuccess = "customer-success"
                case firstParty = "first party"
                case hosting = "hosting"
                case marketing = "marketing"
                case other = "other"
                case social = "social"
                case tagManager = "tag-manager"
                case utility = "utility"
                case video = "video"
            }
        }

        /// Redirect phase properties
        public struct Redirect: Codable {
            /// Duration in ns of the resource redirect phase
            public let duration: Int64

            /// Duration in ns between start of the request and start of the redirect phase
            public let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// SSL phase properties
        public struct SSL: Codable {
            /// Duration in ns of the resource ssl phase
            public let duration: Int64

            /// Duration in ns between start of the request and start of the ssl phase
            public let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// Resource type
        public enum ResourceType: String, Codable {
            case document = "document"
            case xhr = "xhr"
            case beacon = "beacon"
            case fetch = "fetch"
            case css = "css"
            case js = "js"
            case image = "image"
            case font = "font"
            case media = "media"
            case other = "other"
            case native = "native"
        }
    }

    /// Session properties
    public struct Session: Codable {
        /// Whether this session has a replay
        public let hasReplay: Bool?

        /// UUID of the session
        public let id: String

        /// Type of the session
        public let type: SessionType

        enum CodingKeys: String, CodingKey {
            case hasReplay = "has_replay"
            case id = "id"
            case type = "type"
        }

        /// Type of the session
        public enum SessionType: String, Codable {
            case user = "user"
            case synthetics = "synthetics"
            case ciTest = "ci_test"
        }
    }

    /// The source of this event
    public enum Source: String, Codable {
        case android = "android"
        case ios = "ios"
        case browser = "browser"
        case flutter = "flutter"
        case reactNative = "react-native"
        case roku = "roku"
    }

    /// Synthetics properties
    public struct Synthetics: Codable {
        /// Whether the event comes from a SDK instance injected by Synthetics
        public let injected: Bool?

        /// The identifier of the current Synthetics test results
        public let resultId: String

        /// The identifier of the current Synthetics test
        public let testId: String

        enum CodingKeys: String, CodingKey {
            case injected = "injected"
            case resultId = "result_id"
            case testId = "test_id"
        }
    }

    /// View properties
    public struct View: Codable {
        /// UUID of the view
        public let id: String

        /// User defined name of the view
        public var name: String?

        /// URL that linked to the initial view of the page
        public var referrer: String?

        /// URL of the view
        public var url: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case name = "name"
            case referrer = "referrer"
            case url = "url"
        }
    }
}

/// Schema of all properties of a View event
public struct RUMViewEvent: RUMDataModel {
    /// Internal properties
    public let dd: DD

    /// Application properties
    public let application: Application

    /// CI Visibility properties
    public let ciTest: RUMCITest?

    /// Device connectivity properties
    public let connectivity: RUMConnectivity?

    /// User provided context
    public internal(set) var context: RUMEventAttributes?

    /// Start of the event in ms from epoch
    public let date: Int64

    /// Device properties
    public let device: RUMDevice?

    /// Display properties
    public let display: RUMDisplay?

    /// Feature flags properties
    public internal(set) var featureFlags: FeatureFlags?

    /// Operating system properties
    public let os: RUMOperatingSystem?

    /// The service name for this application
    public let service: String?

    /// Session properties
    public let session: Session

    /// The source of this event
    public let source: Source?

    /// Synthetics properties
    public let synthetics: Synthetics?

    /// RUM event type
    public let type: String = "view"

    /// User properties
    public internal(set) var usr: RUMUser?

    /// The version for this application
    public let version: String?

    /// View properties
    public var view: View

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case application = "application"
        case ciTest = "ci_test"
        case connectivity = "connectivity"
        case context = "context"
        case date = "date"
        case device = "device"
        case display = "display"
        case featureFlags = "feature_flags"
        case os = "os"
        case service = "service"
        case session = "session"
        case source = "source"
        case synthetics = "synthetics"
        case type = "type"
        case usr = "usr"
        case version = "version"
        case view = "view"
    }

    /// Internal properties
    public struct DD: Codable {
        /// Browser SDK version
        public let browserSdkVersion: String?

        /// Version of the update of the view event
        public let documentVersion: Int64

        /// Version of the RUM event format
        public let formatVersion: Int64 = 2

        /// Session-related internal properties
        public let session: Session?

        enum CodingKeys: String, CodingKey {
            case browserSdkVersion = "browser_sdk_version"
            case documentVersion = "document_version"
            case formatVersion = "format_version"
            case session = "session"
        }

        /// Session-related internal properties
        public struct Session: Codable {
            /// Session plan: 1 is the plan without replay, 2 is the plan with replay
            public let plan: Plan

            enum CodingKeys: String, CodingKey {
                case plan = "plan"
            }

            /// Session plan: 1 is the plan without replay, 2 is the plan with replay
            public enum Plan: Int, Codable {
                case plan1 = 1
                case plan2 = 2
            }
        }
    }

    /// Application properties
    public struct Application: Codable {
        /// UUID of the application
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Feature flags properties
    public struct FeatureFlags: Codable {
        public internal(set) var featureFlagsInfo: [String: Encodable]
    }

    /// Session properties
    public struct Session: Codable {
        /// Whether this session has a replay
        public let hasReplay: Bool?

        /// UUID of the session
        public let id: String

        /// Type of the session
        public let type: SessionType

        enum CodingKeys: String, CodingKey {
            case hasReplay = "has_replay"
            case id = "id"
            case type = "type"
        }

        /// Type of the session
        public enum SessionType: String, Codable {
            case user = "user"
            case synthetics = "synthetics"
            case ciTest = "ci_test"
        }
    }

    /// The source of this event
    public enum Source: String, Codable {
        case android = "android"
        case ios = "ios"
        case browser = "browser"
        case flutter = "flutter"
        case reactNative = "react-native"
        case roku = "roku"
    }

    /// Synthetics properties
    public struct Synthetics: Codable {
        /// Whether the event comes from a SDK instance injected by Synthetics
        public let injected: Bool?

        /// The identifier of the current Synthetics test results
        public let resultId: String

        /// The identifier of the current Synthetics test
        public let testId: String

        enum CodingKeys: String, CodingKey {
            case injected = "injected"
            case resultId = "result_id"
            case testId = "test_id"
        }
    }

    /// View properties
    public struct View: Codable {
        /// Properties of the actions of the view
        public let action: Action

        /// Total number of cpu ticks during the view’s lifetime
        public let cpuTicksCount: Double?

        /// Average number of cpu ticks per second during the view’s lifetime
        public let cpuTicksPerSecond: Double?

        /// Properties of the crashes of the view
        public let crash: Crash?

        /// Total layout shift score that occurred on the view
        public let cumulativeLayoutShift: Double?

        /// User custom timings of the view. As timing name is used as facet path, it must contain only letters, digits, or the characters - _ . @ $
        public let customTimings: [String: Int64]?

        /// Duration in ns to the complete parsing and loading of the document and its sub resources
        public let domComplete: Int64?

        /// Duration in ns to the complete parsing and loading of the document without its sub resources
        public let domContentLoaded: Int64?

        /// Duration in ns to the end of the parsing of the document
        public let domInteractive: Int64?

        /// Properties of the errors of the view
        public let error: Error

        /// Duration in ns to the response start of the document request
        public let firstByte: Int64?

        /// Duration in ns to the first rendering
        public let firstContentfulPaint: Int64?

        /// Duration in ns of the first input event delay
        public let firstInputDelay: Int64?

        /// Duration in ns to the first input
        public let firstInputTime: Int64?

        /// Time taken for Flutter 'build' methods.
        public let flutterBuildTime: FlutterBuildTime?

        /// Time taken for Flutter to rasterize the view.
        public let flutterRasterTime: FlutterRasterTime?

        /// Properties of the frozen frames of the view
        public let frozenFrame: FrozenFrame?

        /// Properties of the frustrations of the view
        public let frustration: Frustration?

        /// UUID of the view
        public let id: String

        /// List of the periods of time the user had the view in foreground (focused in the browser)
        public let inForegroundPeriods: [InForegroundPeriods]?

        /// Whether the View corresponding to this event is considered active
        public let isActive: Bool?

        /// Whether the View had a low average refresh rate
        public let isSlowRendered: Bool?

        /// The JavaScript refresh rate for React Native
        public let jsRefreshRate: JsRefreshRate?

        /// Duration in ns to the largest contentful paint
        public let largestContentfulPaint: Int64?

        /// Duration in ns to the end of the load event handler execution
        public let loadEvent: Int64?

        /// Duration in ns to the view is considered loaded
        public let loadingTime: Int64?

        /// Type of the loading of the view
        public let loadingType: LoadingType?

        /// Properties of the long tasks of the view
        public let longTask: LongTask?

        /// Average memory used during the view lifetime (in bytes)
        public let memoryAverage: Double?

        /// Peak memory used during the view lifetime (in bytes)
        public let memoryMax: Double?

        /// User defined name of the view
        public var name: String?

        /// URL that linked to the initial view of the page
        public var referrer: String?

        /// Average refresh rate during the view’s lifetime (in frames per second)
        public let refreshRateAverage: Double?

        /// Minimum refresh rate during the view’s lifetime (in frames per second)
        public let refreshRateMin: Double?

        /// Properties of the resources of the view
        public let resource: Resource

        /// Time spent on the view in ns
        public let timeSpent: Int64

        /// URL of the view
        public var url: String

        enum CodingKeys: String, CodingKey {
            case action = "action"
            case cpuTicksCount = "cpu_ticks_count"
            case cpuTicksPerSecond = "cpu_ticks_per_second"
            case crash = "crash"
            case cumulativeLayoutShift = "cumulative_layout_shift"
            case customTimings = "custom_timings"
            case domComplete = "dom_complete"
            case domContentLoaded = "dom_content_loaded"
            case domInteractive = "dom_interactive"
            case error = "error"
            case firstByte = "first_byte"
            case firstContentfulPaint = "first_contentful_paint"
            case firstInputDelay = "first_input_delay"
            case firstInputTime = "first_input_time"
            case flutterBuildTime = "flutter_build_time"
            case flutterRasterTime = "flutter_raster_time"
            case frozenFrame = "frozen_frame"
            case frustration = "frustration"
            case id = "id"
            case inForegroundPeriods = "in_foreground_periods"
            case isActive = "is_active"
            case isSlowRendered = "is_slow_rendered"
            case jsRefreshRate = "js_refresh_rate"
            case largestContentfulPaint = "largest_contentful_paint"
            case loadEvent = "load_event"
            case loadingTime = "loading_time"
            case loadingType = "loading_type"
            case longTask = "long_task"
            case memoryAverage = "memory_average"
            case memoryMax = "memory_max"
            case name = "name"
            case referrer = "referrer"
            case refreshRateAverage = "refresh_rate_average"
            case refreshRateMin = "refresh_rate_min"
            case resource = "resource"
            case timeSpent = "time_spent"
            case url = "url"
        }

        /// Properties of the actions of the view
        public struct Action: Codable {
            /// Number of actions that occurred on the view
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the crashes of the view
        public struct Crash: Codable {
            /// Number of crashes that occurred on the view
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the errors of the view
        public struct Error: Codable {
            /// Number of errors that occurred on the view
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Time taken for Flutter 'build' methods.
        public struct FlutterBuildTime: Codable {
            /// The average value for this metric during the view's lifetime.
            public let average: Double

            /// The maximum value seen for this metric during the view's lifetime.
            public let max: Double

            /// The maximum possible value we could see for this metric, if such a max is relevant and can vary from session to session.
            public let metricMax: Double?

            /// The minimum value seen for this metric during the view's lifetime.
            public let min: Double

            enum CodingKeys: String, CodingKey {
                case average = "average"
                case max = "max"
                case metricMax = "metric_max"
                case min = "min"
            }
        }

        /// Time taken for Flutter to rasterize the view.
        public struct FlutterRasterTime: Codable {
            /// The average value for this metric during the view's lifetime.
            public let average: Double

            /// The maximum value seen for this metric during the view's lifetime.
            public let max: Double

            /// The maximum possible value we could see for this metric, if such a max is relevant and can vary from session to session.
            public let metricMax: Double?

            /// The minimum value seen for this metric during the view's lifetime.
            public let min: Double

            enum CodingKeys: String, CodingKey {
                case average = "average"
                case max = "max"
                case metricMax = "metric_max"
                case min = "min"
            }
        }

        /// Properties of the frozen frames of the view
        public struct FrozenFrame: Codable {
            /// Number of frozen frames that occurred on the view
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the frustrations of the view
        public struct Frustration: Codable {
            /// Number of frustrations that occurred on the view
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the foreground period of the view
        public struct InForegroundPeriods: Codable {
            /// Duration in ns of the view foreground period
            public let duration: Int64

            /// Duration in ns between start of the view and start of foreground period
            public let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// The JavaScript refresh rate for React Native
        public struct JsRefreshRate: Codable {
            /// The average value for this metric during the view's lifetime.
            public let average: Double

            /// The maximum value seen for this metric during the view's lifetime.
            public let max: Double

            /// The maximum possible value we could see for this metric, if such a max is relevant and can vary from session to session.
            public let metricMax: Double?

            /// The minimum value seen for this metric during the view's lifetime.
            public let min: Double

            enum CodingKeys: String, CodingKey {
                case average = "average"
                case max = "max"
                case metricMax = "metric_max"
                case min = "min"
            }
        }

        /// Type of the loading of the view
        public enum LoadingType: String, Codable {
            case initialLoad = "initial_load"
            case routeChange = "route_change"
            case activityDisplay = "activity_display"
            case activityRedisplay = "activity_redisplay"
            case fragmentDisplay = "fragment_display"
            case fragmentRedisplay = "fragment_redisplay"
            case viewControllerDisplay = "view_controller_display"
            case viewControllerRedisplay = "view_controller_redisplay"
        }

        /// Properties of the long tasks of the view
        public struct LongTask: Codable {
            /// Number of long tasks that occurred on the view
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the resources of the view
        public struct Resource: Codable {
            /// Number of resources that occurred on the view
            public let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }
    }
}

extension RUMViewEvent.FeatureFlags {
    public func encode(to encoder: Encoder) throws {
        // Encode dynamic properties:
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try featureFlagsInfo.forEach {
            let key = DynamicCodingKey($0)
            try dynamicContainer.encode(AnyEncodable($1), forKey: key)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode other properties into [String: Codable] dictionary:
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let dynamicKeys = dynamicContainer.allKeys
        var dictionary: [String: Codable] = [:]

        try dynamicKeys.forEach { codingKey in
            dictionary[codingKey.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: codingKey)
        }

        self.featureFlagsInfo = dictionary
    }
}

/// Schema of all properties of a telemetry error event
public struct TelemetryErrorEvent: RUMDataModel {
    /// Internal properties
    public let dd: DD

    /// Action properties
    public let action: Action?

    /// Application properties
    public let application: Application?

    /// Start of the event in ms from epoch
    public let date: Int64

    /// Enabled experimental features
    public let experimentalFeatures: [String]?

    /// The SDK generating the telemetry event
    public let service: String

    /// Session properties
    public let session: Session?

    /// The source of this event
    public let source: Source

    /// The telemetry log information
    public let telemetry: Telemetry

    /// Telemetry event type. Should specify telemetry only.
    public let type: String = "telemetry"

    /// The version of the SDK generating the telemetry event
    public let version: String

    /// View properties
    public let view: View?

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case action = "action"
        case application = "application"
        case date = "date"
        case experimentalFeatures = "experimental_features"
        case service = "service"
        case session = "session"
        case source = "source"
        case telemetry = "telemetry"
        case type = "type"
        case version = "version"
        case view = "view"
    }

    /// Internal properties
    public struct DD: Codable {
        /// Version of the RUM event format
        public let formatVersion: Int64 = 2

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
        }
    }

    /// Action properties
    public struct Action: Codable {
        /// UUID of the action
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Application properties
    public struct Application: Codable {
        /// UUID of the application
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Session properties
    public struct Session: Codable {
        /// UUID of the session
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// The source of this event
    public enum Source: String, Codable {
        case android = "android"
        case ios = "ios"
        case browser = "browser"
        case flutter = "flutter"
        case reactNative = "react-native"
    }

    /// The telemetry log information
    public struct Telemetry: Codable {
        /// Error properties
        public let error: Error?

        /// Body of the log
        public let message: String

        /// Level/severity of the log
        public let status: String = "error"

        /// Telemetry type
        public let type: String? = "log"

        enum CodingKeys: String, CodingKey {
            case error = "error"
            case message = "message"
            case status = "status"
            case type = "type"
        }

        /// Error properties
        public struct Error: Codable {
            /// The error type or kind (or code in some cases)
            public let kind: String?

            /// The stack trace or the complementary information about the error
            public let stack: String?

            enum CodingKeys: String, CodingKey {
                case kind = "kind"
                case stack = "stack"
            }
        }
    }

    /// View properties
    public struct View: Codable {
        /// UUID of the view
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }
}

/// Schema of all properties of a telemetry debug event
public struct TelemetryDebugEvent: RUMDataModel {
    /// Internal properties
    public let dd: DD

    /// Action properties
    public let action: Action?

    /// Application properties
    public let application: Application?

    /// Start of the event in ms from epoch
    public let date: Int64

    /// Enabled experimental features
    public let experimentalFeatures: [String]?

    /// The SDK generating the telemetry event
    public let service: String

    /// Session properties
    public let session: Session?

    /// The source of this event
    public let source: Source

    /// The telemetry log information
    public let telemetry: Telemetry

    /// Telemetry event type. Should specify telemetry only.
    public let type: String = "telemetry"

    /// The version of the SDK generating the telemetry event
    public let version: String

    /// View properties
    public let view: View?

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case action = "action"
        case application = "application"
        case date = "date"
        case experimentalFeatures = "experimental_features"
        case service = "service"
        case session = "session"
        case source = "source"
        case telemetry = "telemetry"
        case type = "type"
        case version = "version"
        case view = "view"
    }

    /// Internal properties
    public struct DD: Codable {
        /// Version of the RUM event format
        public let formatVersion: Int64 = 2

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
        }
    }

    /// Action properties
    public struct Action: Codable {
        /// UUID of the action
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Application properties
    public struct Application: Codable {
        /// UUID of the application
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Session properties
    public struct Session: Codable {
        /// UUID of the session
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// The source of this event
    public enum Source: String, Codable {
        case android = "android"
        case ios = "ios"
        case browser = "browser"
        case flutter = "flutter"
        case reactNative = "react-native"
    }

    /// The telemetry log information
    public struct Telemetry: Codable {
        /// Body of the log
        public let message: String

        /// Level/severity of the log
        public let status: String = "debug"

        /// Telemetry type
        public let type: String? = "log"

        enum CodingKeys: String, CodingKey {
            case message = "message"
            case status = "status"
            case type = "type"
        }
    }

    /// View properties
    public struct View: Codable {
        /// UUID of the view
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }
}

/// Schema of all properties of a telemetry configuration event
public struct TelemetryConfigurationEvent: RUMDataModel {
    /// Internal properties
    public let dd: DD

    /// Action properties
    public let action: Action?

    /// Application properties
    public let application: Application?

    /// Start of the event in ms from epoch
    public let date: Int64

    /// Enabled experimental features
    public let experimentalFeatures: [String]?

    /// The SDK generating the telemetry event
    public let service: String

    /// Session properties
    public let session: Session?

    /// The source of this event
    public let source: Source

    /// The telemetry configuration information
    public var telemetry: Telemetry

    /// Telemetry event type. Should specify telemetry only.
    public let type: String = "telemetry"

    /// The version of the SDK generating the telemetry event
    public let version: String

    /// View properties
    public let view: View?

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case action = "action"
        case application = "application"
        case date = "date"
        case experimentalFeatures = "experimental_features"
        case service = "service"
        case session = "session"
        case source = "source"
        case telemetry = "telemetry"
        case type = "type"
        case version = "version"
        case view = "view"
    }

    /// Internal properties
    public struct DD: Codable {
        /// Version of the RUM event format
        public let formatVersion: Int64 = 2

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
        }
    }

    /// Action properties
    public struct Action: Codable {
        /// UUID of the action
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Application properties
    public struct Application: Codable {
        /// UUID of the application
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Session properties
    public struct Session: Codable {
        /// UUID of the session
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// The source of this event
    public enum Source: String, Codable {
        case android = "android"
        case ios = "ios"
        case browser = "browser"
        case flutter = "flutter"
        case reactNative = "react-native"
    }

    /// The telemetry configuration information
    public struct Telemetry: Codable {
        /// Configuration properties
        public var configuration: Configuration

        /// Telemetry type
        public let type: String = "configuration"

        enum CodingKeys: String, CodingKey {
            case configuration = "configuration"
            case type = "type"
        }

        /// Configuration properties
        public struct Configuration: Codable {
            /// Attribute to be used to name actions
            public let actionNameAttribute: String?

            /// The window duration for batches sent by the SDK (in milliseconds)
            public let batchSize: Int64?

            /// The upload frequency of batches (in milliseconds)
            public let batchUploadFrequency: Int64?

            /// Session replay default privacy level
            public var defaultPrivacyLevel: String?

            /// The console.* tracked
            public let forwardConsoleLogs: ForwardConsoleLogs?

            /// Whether console.error logs, uncaught exceptions and network errors are tracked
            public let forwardErrorsToLogs: Bool?

            /// The reports from the Reporting API tracked
            public let forwardReports: ForwardReports?

            /// The type of initialization the SDK used, in case multiple are supported
            public var initializationType: String?

            /// The period between each Mobile Vital sample (in milliseconds)
            public var mobileVitalsUpdatePeriod: Int64?

            /// The percentage of sessions with Browser RUM & Session Replay pricing tracked (deprecated in favor of session_replay_sample_rate)
            public let premiumSampleRate: Int64?

            /// The percentage of sessions with Browser RUM & Session Replay pricing tracked (deprecated in favor of session_replay_sample_rate)
            public let replaySampleRate: Int64?

            /// The percentage of sessions with Browser RUM & Session Replay pricing tracked
            public var sessionReplaySampleRate: Int64?

            /// The percentage of sessions tracked
            public let sessionSampleRate: Int64?

            /// Whether initialization fails silently if the SDK is already initialized
            public let silentMultipleInit: Bool?

            /// The percentage of telemetry configuration events sent after being sampled by telemetry_sample_rate
            public let telemetryConfigurationSampleRate: Int64?

            /// The percentage of telemetry events sent
            public let telemetrySampleRate: Int64?

            /// The percentage of requests traced
            public let traceSampleRate: Int64?

            /// Whether RUM events are tracked when the application is in Background
            public var trackBackgroundEvents: Bool?

            /// Whether long task tracking is performed automatically for cross platform SDKs
            public var trackCrossPlatformLongTasks: Bool?

            /// Whether error monitoring & crash reporting is enabled for the source platform
            public var trackErrors: Bool?

            /// Whether Flutter build and raster time tracking is enabled
            public var trackFlutterPerformance: Bool?

            /// Whether user frustrations are tracked
            public var trackFrustrations: Bool?

            /// Whether user actions are tracked
            public var trackInteractions: Bool?

            /// Whether long tasks are tracked
            public var trackLongTask: Bool?

            /// Whether native error monitoring & crash reporting is enabled (for cross platform SDKs)
            public var trackNativeErrors: Bool?

            /// Whether long task tracking is performed automatically
            public var trackNativeLongTasks: Bool?

            /// Whether native views are tracked (for cross platform SDKs)
            public var trackNativeViews: Bool?

            /// Whether automatic collection of network requests is enabled
            public var trackNetworkRequests: Bool?

            /// Whether resources are tracked
            public var trackResources: Bool?

            /// Whether sessions across subdomains for the same site are tracked
            public let trackSessionAcrossSubdomains: Bool?

            /// Whether the RUM views creation is handled manually
            public var trackViewsManually: Bool?

            /// Whether the allowed tracing origins list is used
            public let useAllowedTracingOrigins: Bool?

            /// Whether beforeSend callback function is used
            public let useBeforeSend: Bool?

            /// Whether a secure cross-site session cookie is used
            public let useCrossSiteSessionCookie: Bool?

            /// Whether the request origins list to ignore when computing the page activity is used
            public let useExcludedActivityUrls: Bool?

            /// Whether the client has provided a list of first party hosts
            public var useFirstPartyHosts: Bool?

            /// Whether local encryption is used
            public let useLocalEncryption: Bool?

            /// Whether a proxy configured is used
            public var useProxy: Bool?

            /// Whether a secure session cookie is used
            public let useSecureSessionCookie: Bool?

            /// Whether tracing features are enabled
            public let useTracing: Bool?

            /// View tracking strategy
            public let viewTrackingStrategy: ViewTrackingStrategy?

            enum CodingKeys: String, CodingKey {
                case actionNameAttribute = "action_name_attribute"
                case batchSize = "batch_size"
                case batchUploadFrequency = "batch_upload_frequency"
                case defaultPrivacyLevel = "default_privacy_level"
                case forwardConsoleLogs = "forward_console_logs"
                case forwardErrorsToLogs = "forward_errors_to_logs"
                case forwardReports = "forward_reports"
                case initializationType = "initialization_type"
                case mobileVitalsUpdatePeriod = "mobile_vitals_update_period"
                case premiumSampleRate = "premium_sample_rate"
                case replaySampleRate = "replay_sample_rate"
                case sessionReplaySampleRate = "session_replay_sample_rate"
                case sessionSampleRate = "session_sample_rate"
                case silentMultipleInit = "silent_multiple_init"
                case telemetryConfigurationSampleRate = "telemetry_configuration_sample_rate"
                case telemetrySampleRate = "telemetry_sample_rate"
                case traceSampleRate = "trace_sample_rate"
                case trackBackgroundEvents = "track_background_events"
                case trackCrossPlatformLongTasks = "track_cross_platform_long_tasks"
                case trackErrors = "track_errors"
                case trackFlutterPerformance = "track_flutter_performance"
                case trackFrustrations = "track_frustrations"
                case trackInteractions = "track_interactions"
                case trackLongTask = "track_long_task"
                case trackNativeErrors = "track_native_errors"
                case trackNativeLongTasks = "track_native_long_tasks"
                case trackNativeViews = "track_native_views"
                case trackNetworkRequests = "track_network_requests"
                case trackResources = "track_resources"
                case trackSessionAcrossSubdomains = "track_session_across_subdomains"
                case trackViewsManually = "track_views_manually"
                case useAllowedTracingOrigins = "use_allowed_tracing_origins"
                case useBeforeSend = "use_before_send"
                case useCrossSiteSessionCookie = "use_cross_site_session_cookie"
                case useExcludedActivityUrls = "use_excluded_activity_urls"
                case useFirstPartyHosts = "use_first_party_hosts"
                case useLocalEncryption = "use_local_encryption"
                case useProxy = "use_proxy"
                case useSecureSessionCookie = "use_secure_session_cookie"
                case useTracing = "use_tracing"
                case viewTrackingStrategy = "view_tracking_strategy"
            }

            /// The console.* tracked
            public enum ForwardConsoleLogs: Codable {
                case stringsArray(value: [String])
                case string(value: String)

                // MARK: - Codable

                public func encode(to encoder: Encoder) throws {
                    // Encode only the associated value, without encoding enum case
                    var container = encoder.singleValueContainer()

                    switch self {
                    case .stringsArray(let value):
                        try container.encode(value)
                    case .string(let value):
                        try container.encode(value)
                    }
                }

                public init(from decoder: Decoder) throws {
                    // Decode enum case from associated value
                    let container = try decoder.singleValueContainer()

                    if let value = try? container.decode([String].self) {
                        self = .stringsArray(value: value)
                        return
                    }
                    if let value = try? container.decode(String.self) {
                        self = .string(value: value)
                        return
                    }
                    let error = DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: """
                        Failed to decode `ForwardConsoleLogs`.
                        Ran out of possibilities when trying to decode the value of associated type.
                        """
                    )
                    throw DecodingError.typeMismatch(ForwardConsoleLogs.self, error)
                }
            }

            /// The reports from the Reporting API tracked
            public enum ForwardReports: Codable {
                case stringsArray(value: [String])
                case string(value: String)

                // MARK: - Codable

                public func encode(to encoder: Encoder) throws {
                    // Encode only the associated value, without encoding enum case
                    var container = encoder.singleValueContainer()

                    switch self {
                    case .stringsArray(let value):
                        try container.encode(value)
                    case .string(let value):
                        try container.encode(value)
                    }
                }

                public init(from decoder: Decoder) throws {
                    // Decode enum case from associated value
                    let container = try decoder.singleValueContainer()

                    if let value = try? container.decode([String].self) {
                        self = .stringsArray(value: value)
                        return
                    }
                    if let value = try? container.decode(String.self) {
                        self = .string(value: value)
                        return
                    }
                    let error = DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: """
                        Failed to decode `ForwardReports`.
                        Ran out of possibilities when trying to decode the value of associated type.
                        """
                    )
                    throw DecodingError.typeMismatch(ForwardReports.self, error)
                }
            }

            /// View tracking strategy
            public enum ViewTrackingStrategy: String, Codable {
                case activityViewTrackingStrategy = "ActivityViewTrackingStrategy"
                case fragmentViewTrackingStrategy = "FragmentViewTrackingStrategy"
                case mixedViewTrackingStrategy = "MixedViewTrackingStrategy"
                case navigationViewTrackingStrategy = "NavigationViewTrackingStrategy"
            }
        }
    }

    /// View properties
    public struct View: Codable {
        /// UUID of the view
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }
}

/// CI Visibility properties
public struct RUMCITest: Codable {
    /// The identifier of the current CI Visibility test execution
    public let testExecutionId: String

    enum CodingKeys: String, CodingKey {
        case testExecutionId = "test_execution_id"
    }
}

/// Device connectivity properties
public struct RUMConnectivity: Codable {
    /// Cellular connectivity properties
    public let cellular: Cellular?

    /// The list of available network interfaces
    public let interfaces: [Interfaces]

    /// Status of the device connectivity
    public let status: Status

    enum CodingKeys: String, CodingKey {
        case cellular = "cellular"
        case interfaces = "interfaces"
        case status = "status"
    }

    /// Cellular connectivity properties
    public struct Cellular: Codable {
        /// The name of the SIM carrier
        public let carrierName: String?

        /// The type of a radio technology used for cellular connection
        public let technology: String?

        enum CodingKeys: String, CodingKey {
            case carrierName = "carrier_name"
            case technology = "technology"
        }
    }

    public enum Interfaces: String, Codable {
        case bluetooth = "bluetooth"
        case cellular = "cellular"
        case ethernet = "ethernet"
        case wifi = "wifi"
        case wimax = "wimax"
        case mixed = "mixed"
        case other = "other"
        case unknown = "unknown"
        case none = "none"
    }

    /// Status of the device connectivity
    public enum Status: String, Codable {
        case connected = "connected"
        case notConnected = "not_connected"
        case maybe = "maybe"
    }
}

/// User provided context
public struct RUMEventAttributes: Codable {
    public internal(set) var contextInfo: [String: Encodable]
}

extension RUMEventAttributes {
    public func encode(to encoder: Encoder) throws {
        // Encode dynamic properties:
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try contextInfo.forEach {
            let key = DynamicCodingKey($0)
            try dynamicContainer.encode(AnyEncodable($1), forKey: key)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode other properties into [String: Codable] dictionary:
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let dynamicKeys = dynamicContainer.allKeys
        var dictionary: [String: Codable] = [:]

        try dynamicKeys.forEach { codingKey in
            dictionary[codingKey.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: codingKey)
        }

        self.contextInfo = dictionary
    }
}

/// Device properties
public struct RUMDevice: Codable {
    /// The CPU architecture of the device that is reporting the error
    public let architecture: String?

    /// Device marketing brand, e.g. Apple, OPPO, Xiaomi, etc.
    public let brand: String?

    /// Device SKU model, e.g. Samsung SM-988GN, etc. Quite often name and model can be the same.
    public let model: String?

    /// Device marketing name, e.g. Xiaomi Redmi Note 8 Pro, Pixel 5, etc.
    public let name: String?

    /// Device type info
    public let type: RUMDeviceType

    enum CodingKeys: String, CodingKey {
        case architecture = "architecture"
        case brand = "brand"
        case model = "model"
        case name = "name"
        case type = "type"
    }

    /// Device type info
    public enum RUMDeviceType: String, Codable {
        case mobile = "mobile"
        case desktop = "desktop"
        case tablet = "tablet"
        case tv = "tv"
        case gamingConsole = "gaming_console"
        case bot = "bot"
        case other = "other"
    }
}

/// Display properties
public struct RUMDisplay: Codable {
    /// The viewport represents the rectangular area that is currently being viewed. Content outside the viewport is not visible onscreen until scrolled into view.
    public let viewport: Viewport?

    enum CodingKeys: String, CodingKey {
        case viewport = "viewport"
    }

    /// The viewport represents the rectangular area that is currently being viewed. Content outside the viewport is not visible onscreen until scrolled into view.
    public struct Viewport: Codable {
        /// Height of the viewport (in pixels)
        public let height: Double

        /// Width of the viewport (in pixels)
        public let width: Double

        enum CodingKeys: String, CodingKey {
            case height = "height"
            case width = "width"
        }
    }
}

/// Operating system properties
public struct RUMOperatingSystem: Codable {
    /// Operating system name, e.g. Android, iOS
    public let name: String

    /// Full operating system version, e.g. 8.1.1
    public let version: String

    /// Major operating system version, e.g. 8
    public let versionMajor: String

    enum CodingKeys: String, CodingKey {
        case name = "name"
        case version = "version"
        case versionMajor = "version_major"
    }
}

/// User properties
public struct RUMUser: Codable {
    /// Email of the user
    public let email: String?

    /// Identifier of the user
    public let id: String?

    /// Name of the user
    public let name: String?

    public internal(set) var usrInfo: [String: Encodable]

    enum StaticCodingKeys: String, CodingKey {
        case email = "email"
        case id = "id"
        case name = "name"
    }
}

extension RUMUser {
    public func encode(to encoder: Encoder) throws {
        // Encode static properties:
        var staticContainer = encoder.container(keyedBy: StaticCodingKeys.self)
        try staticContainer.encodeIfPresent(email, forKey: .email)
        try staticContainer.encodeIfPresent(id, forKey: .id)
        try staticContainer.encodeIfPresent(name, forKey: .name)

        // Encode dynamic properties:
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try usrInfo.forEach {
            let key = DynamicCodingKey($0)
            try dynamicContainer.encode(AnyEncodable($1), forKey: key)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode static properties:
        let staticContainer = try decoder.container(keyedBy: StaticCodingKeys.self)
        self.email = try staticContainer.decodeIfPresent(String.self, forKey: .email)
        self.id = try staticContainer.decodeIfPresent(String.self, forKey: .id)
        self.name = try staticContainer.decodeIfPresent(String.self, forKey: .name)

        // Decode other properties into [String: Codable] dictionary:
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let allStaticKeys = Set(staticContainer.allKeys.map { $0.stringValue })
        let dynamicKeys = dynamicContainer.allKeys.filter { !allStaticKeys.contains($0.stringValue) }
        var dictionary: [String: Codable] = [:]

        try dynamicKeys.forEach { codingKey in
            dictionary[codingKey.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: codingKey)
        }

        self.usrInfo = dictionary
    }
}

/// UUID of the action
public enum RUMActionID: Codable {
    case string(value: String)
    case stringsArray(value: [String])

    // MARK: - Codable

    public func encode(to encoder: Encoder) throws {
        // Encode only the associated value, without encoding enum case
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .stringsArray(let value):
            try container.encode(value)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode enum case from associated value
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value: value)
            return
        }
        if let value = try? container.decode([String].self) {
            self = .stringsArray(value: value)
            return
        }
        let error = DecodingError.Context(
            codingPath: container.codingPath,
            debugDescription: """
            Failed to decode `RUMActionID`.
            Ran out of possibilities when trying to decode the value of associated type.
            """
        )
        throw DecodingError.typeMismatch(RUMActionID.self, error)
    }
}

/// HTTP method of the resource
public enum RUMMethod: String, Codable {
    case post = "POST"
    case get = "GET"
    case head = "HEAD"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

// Generated from https://github.com/DataDog/rum-events-format/tree/083edbb0f9fec392224820bd05c6336ce6d62c30
