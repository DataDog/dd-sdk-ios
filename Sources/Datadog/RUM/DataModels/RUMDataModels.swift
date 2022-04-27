/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

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
            /// Session plan: 1 is the 'lite' plan, 2 is the 'replay' plan
            public let plan: Plan

            enum CodingKeys: String, CodingKey {
                case plan = "plan"
            }

            /// Session plan: 1 is the 'lite' plan, 2 is the 'replay' plan
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

        /// Action frustration types
        public let frustrationType: [FrustrationType]?

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
            case frustrationType = "frustration_type"
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

        public enum FrustrationType: String, Codable {
            case rage = "rage"
            case dead = "dead"
            case error = "error"
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

    /// Error properties
    public var error: Error

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
        case error = "error"
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
            /// Session plan: 1 is the 'lite' plan, 2 is the 'replay' plan
            public let plan: Plan

            enum CodingKeys: String, CodingKey {
                case plan = "plan"
            }

            /// Session plan: 1 is the 'lite' plan, 2 is the 'replay' plan
            public enum Plan: Int, Codable {
                case plan1 = 1
                case plan2 = 2
            }
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

    /// Error properties
    public struct Error: Codable {
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

    /// Long Task properties
    public let longTask: LongTask

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
        case longTask = "long_task"
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
            /// Session plan: 1 is the 'lite' plan, 2 is the 'replay' plan
            public let plan: Plan

            enum CodingKeys: String, CodingKey {
                case plan = "plan"
            }

            /// Session plan: 1 is the 'lite' plan, 2 is the 'replay' plan
            public enum Plan: Int, Codable {
                case plan1 = 1
                case plan2 = 2
            }
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

        /// Version of the RUM event format
        public let formatVersion: Int64 = 2

        /// Session-related internal properties
        public let session: Session?

        /// span identifier in decimal format
        public let spanId: String?

        /// trace identifier in decimal format
        public let traceId: String?

        enum CodingKeys: String, CodingKey {
            case browserSdkVersion = "browser_sdk_version"
            case formatVersion = "format_version"
            case session = "session"
            case spanId = "span_id"
            case traceId = "trace_id"
        }

        /// Session-related internal properties
        public struct Session: Codable {
            /// Session plan: 1 is the 'lite' plan, 2 is the 'replay' plan
            public let plan: Plan

            enum CodingKeys: String, CodingKey {
                case plan = "plan"
            }

            /// Session plan: 1 is the 'lite' plan, 2 is the 'replay' plan
            public enum Plan: Int, Codable {
                case plan1 = 1
                case plan2 = 2
            }
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
            /// Session plan: 1 is the 'lite' plan, 2 is the 'replay' plan
            public let plan: Plan

            enum CodingKeys: String, CodingKey {
                case plan = "plan"
            }

            /// Session plan: 1 is the 'lite' plan, 2 is the 'replay' plan
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

        /// Total layout shift score that occured on the view
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

        /// Duration in ns to the first rendering
        public let firstContentfulPaint: Int64?

        /// Duration in ns of the first input event delay
        public let firstInputDelay: Int64?

        /// Duration in ns to the first input
        public let firstInputTime: Int64?

        /// Properties of the frozen frames of the view
        public let frozenFrame: FrozenFrame?

        /// UUID of the view
        public let id: String

        /// List of the periods of time the user had the view in foreground (focused in the browser)
        public let inForegroundPeriods: [InForegroundPeriods]?

        /// Whether the View corresponding to this event is considered active
        public let isActive: Bool?

        /// Whether the View had a low average refresh rate
        public let isSlowRendered: Bool?

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
            case firstContentfulPaint = "first_contentful_paint"
            case firstInputDelay = "first_input_delay"
            case firstInputTime = "first_input_time"
            case frozenFrame = "frozen_frame"
            case id = "id"
            case inForegroundPeriods = "in_foreground_periods"
            case isActive = "is_active"
            case isSlowRendered = "is_slow_rendered"
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

        /// Properties of the frozen frames of the view
        public struct FrozenFrame: Codable {
            /// Number of frozen frames that occurred on the view
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

    /// The SDK generating the telemetry event
    public let service: String

    /// Session properties
    public let session: Session?

    /// The source of this event
    public let source: Source

    /// The telemetry information
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

    /// The telemetry information
    public struct Telemetry: Codable {
        /// Error properties
        public let error: Error?

        /// Body of the log
        public let message: String

        /// Level/severity of the log
        public let status: String = "error"

        enum CodingKeys: String, CodingKey {
            case error = "error"
            case message = "message"
            case status = "status"
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

    /// The SDK generating the telemetry event
    public let service: String

    /// Session properties
    public let session: Session?

    /// The source of this event
    public let source: Source

    /// The telemetry information
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

    /// The telemetry information
    public struct Telemetry: Codable {
        /// Body of the log
        public let message: String

        /// Level/severity of the log
        public let status: String = "debug"

        enum CodingKeys: String, CodingKey {
            case message = "message"
            case status = "status"
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

    struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
    }
}

extension RUMEventAttributes {
    public func encode(to encoder: Encoder) throws {
        // Encode dynamic properties:
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        try contextInfo.forEach {
            let key = DynamicCodingKey($0)
            try dynamicContainer.encode(CodableValue($1), forKey: key)
        }
    }

    public init(from decoder: Decoder) throws {
        // Decode other properties into [String: Codable] dictionary:
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let dynamicKeys = dynamicContainer.allKeys
        var dictionary: [String: Codable] = [:]

        try dynamicKeys.forEach { codingKey in
            dictionary[codingKey.stringValue] = try dynamicContainer.decode(CodableValue.self, forKey: codingKey)
        }

        self.contextInfo = dictionary
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

    struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ string: String) { self.stringValue = string }
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
            try dynamicContainer.encode(CodableValue($1), forKey: key)
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
            dictionary[codingKey.stringValue] = try dynamicContainer.decode(CodableValue.self, forKey: codingKey)
        }

        self.usrInfo = dictionary
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

// Generated from https://github.com/DataDog/rum-events-format/tree/568fc1bcfb0d2775a11c07914120b70a3d5780fe
