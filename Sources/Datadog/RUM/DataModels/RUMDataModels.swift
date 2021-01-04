/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

// This file was generated from JSON Schema. Do not modify it directly.

internal protocol RUMDataModel: Codable {}

/// Schema of all properties of a View event
internal struct RUMViewEvent: RUMDataModel {
    /// Internal properties
    let dd: DD

    /// Application properties
    let application: Application

    /// Device connectivity properties
    let connectivity: RUMConnectivity?

    /// Start of the event in ms from epoch
    let date: Int64

    /// The service name for this application
    let service: String?

    /// Session properties
    let session: Session

    /// RUM event type
    let type: String = "view"

    /// User properties
    let usr: RUMUser?

    /// View properties
    let view: View

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case application = "application"
        case connectivity = "connectivity"
        case date = "date"
        case service = "service"
        case session = "session"
        case type = "type"
        case usr = "usr"
        case view = "view"
    }

    /// Internal properties
    internal struct DD: Codable {
        /// Version of the update of the view event
        let documentVersion: Int64

        /// Version of the RUM event format
        let formatVersion: Int64 = 2

        enum CodingKeys: String, CodingKey {
            case documentVersion = "document_version"
            case formatVersion = "format_version"
        }
    }

    /// Application properties
    internal struct Application: Codable {
        /// UUID of the application
        let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Session properties
    internal struct Session: Codable {
        /// UUID of the session
        let id: String

        /// Type of the session
        let type: SessionType

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case type = "type"
        }

        /// Type of the session
        internal enum SessionType: String, Codable {
            case user = "user"
            case synthetics = "synthetics"
        }
    }

    /// View properties
    internal struct View: Codable {
        /// Properties of the actions of the view
        let action: Action

        /// Properties of the crashes of the view
        let crash: Crash?

        /// Total layout shift score that occured on the view
        let cumulativeLayoutShift: Double?

        /// Duration in ns to the complete parsing and loading of the document and its sub resources
        let domComplete: Int64?

        /// Duration in ns to the complete parsing and loading of the document without its sub resources
        let domContentLoaded: Int64?

        /// Duration in ns to the end of the parsing of the document
        let domInteractive: Int64?

        /// Properties of the errors of the view
        let error: Error

        /// Duration in ns to the first rendering
        let firstContentfulPaint: Int64?

        /// Duration in ns of the first input event delay
        let firstInputDelay: Int64?

        /// UUID of the view
        let id: String

        /// Whether the View corresponding to this event is considered active
        let isActive: Bool?

        /// Duration in ns to the largest contentful paint
        let largestContentfulPaint: Int64?

        /// Duration in ns to the end of the load event handler execution
        let loadEvent: Int64?

        /// Duration in ns to the view is considered loaded
        let loadingTime: Int64?

        /// Type of the loading of the view
        let loadingType: LoadingType?

        /// Properties of the long tasks of the view
        let longTask: LongTask?

        /// URL that linked to the initial view of the page
        var referrer: String?

        /// Properties of the resources of the view
        let resource: Resource

        /// Time spent on the view in ns
        let timeSpent: Int64

        /// URL of the view
        var url: String

        enum CodingKeys: String, CodingKey {
            case action = "action"
            case crash = "crash"
            case cumulativeLayoutShift = "cumulative_layout_shift"
            case domComplete = "dom_complete"
            case domContentLoaded = "dom_content_loaded"
            case domInteractive = "dom_interactive"
            case error = "error"
            case firstContentfulPaint = "first_contentful_paint"
            case firstInputDelay = "first_input_delay"
            case id = "id"
            case isActive = "is_active"
            case largestContentfulPaint = "largest_contentful_paint"
            case loadEvent = "load_event"
            case loadingTime = "loading_time"
            case loadingType = "loading_type"
            case longTask = "long_task"
            case referrer = "referrer"
            case resource = "resource"
            case timeSpent = "time_spent"
            case url = "url"
        }

        /// Properties of the actions of the view
        internal struct Action: Codable {
            /// Number of actions that occurred on the view
            let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the crashes of the view
        internal struct Crash: Codable {
            /// Number of crashes that occurred on the view
            let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the errors of the view
        internal struct Error: Codable {
            /// Number of errors that occurred on the view
            let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Type of the loading of the view
        internal enum LoadingType: String, Codable {
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
        internal struct LongTask: Codable {
            /// Number of long tasks that occurred on the view
            let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the resources of the view
        internal struct Resource: Codable {
            /// Number of resources that occurred on the view
            let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }
    }
}

/// Schema of all properties of a Resource event
internal struct RUMResourceEvent: RUMDataModel {
    /// Internal properties
    let dd: DD

    /// Action properties
    let action: Action?

    /// Application properties
    let application: Application

    /// Device connectivity properties
    let connectivity: RUMConnectivity?

    /// Start of the event in ms from epoch
    let date: Int64

    /// Resource properties
    let resource: Resource

    /// The service name for this application
    let service: String?

    /// Session properties
    let session: Session

    /// RUM event type
    let type: String = "resource"

    /// User properties
    let usr: RUMUser?

    /// View properties
    let view: View

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case action = "action"
        case application = "application"
        case connectivity = "connectivity"
        case date = "date"
        case resource = "resource"
        case service = "service"
        case session = "session"
        case type = "type"
        case usr = "usr"
        case view = "view"
    }

    /// Internal properties
    internal struct DD: Codable {
        /// Version of the RUM event format
        let formatVersion: Int64 = 2

        /// span identifier in decimal format
        let spanId: String?

        /// trace identifier in decimal format
        let traceId: String?

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
            case spanId = "span_id"
            case traceId = "trace_id"
        }
    }

    /// Action properties
    internal struct Action: Codable {
        /// UUID of the action
        let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Application properties
    internal struct Application: Codable {
        /// UUID of the application
        let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Resource properties
    internal struct Resource: Codable {
        /// Connect phase properties
        let connect: Connect?

        /// DNS phase properties
        let dns: DNS?

        /// Download phase properties
        let download: Download?

        /// Duration of the resource
        let duration: Int64

        /// First Byte phase properties
        let firstByte: FirstByte?

        /// UUID of the resource
        let id: String?

        /// HTTP method of the resource
        let method: RUMMethod?

        /// The provider for this resource
        let provider: Provider?

        /// Redirect phase properties
        let redirect: Redirect?

        /// Size in octet of the resource response body
        let size: Int64?

        /// SSL phase properties
        let ssl: SSL?

        /// HTTP status code of the resource
        let statusCode: Int64?

        /// Resource type
        let type: ResourceType

        /// URL of the resource
        var url: String

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
        internal struct Connect: Codable {
            /// Duration in ns of the resource connect phase
            let duration: Int64

            /// Duration in ns between start of the request and start of the connect phase
            let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// DNS phase properties
        internal struct DNS: Codable {
            /// Duration in ns of the resource dns phase
            let duration: Int64

            /// Duration in ns between start of the request and start of the dns phase
            let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// Download phase properties
        internal struct Download: Codable {
            /// Duration in ns of the resource download phase
            let duration: Int64

            /// Duration in ns between start of the request and start of the download phase
            let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// First Byte phase properties
        internal struct FirstByte: Codable {
            /// Duration in ns of the resource first byte phase
            let duration: Int64

            /// Duration in ns between start of the request and start of the first byte phase
            let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// The provider for this resource
        internal struct Provider: Codable {
            /// The domain name of the provider
            let domain: String?

            /// The user friendly name of the provider
            let name: String?

            /// The type of provider
            let type: ProviderType?

            enum CodingKeys: String, CodingKey {
                case domain = "domain"
                case name = "name"
                case type = "type"
            }

            /// The type of provider
            internal enum ProviderType: String, Codable {
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
        internal struct Redirect: Codable {
            /// Duration in ns of the resource redirect phase
            let duration: Int64

            /// Duration in ns between start of the request and start of the redirect phase
            let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// SSL phase properties
        internal struct SSL: Codable {
            /// Duration in ns of the resource ssl phase
            let duration: Int64

            /// Duration in ns between start of the request and start of the ssl phase
            let start: Int64

            enum CodingKeys: String, CodingKey {
                case duration = "duration"
                case start = "start"
            }
        }

        /// Resource type
        internal enum ResourceType: String, Codable {
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
        }
    }

    /// Session properties
    internal struct Session: Codable {
        /// UUID of the session
        let id: String

        /// Type of the session
        let type: SessionType

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case type = "type"
        }

        /// Type of the session
        internal enum SessionType: String, Codable {
            case user = "user"
            case synthetics = "synthetics"
        }
    }

    /// View properties
    internal struct View: Codable {
        /// UUID of the view
        let id: String

        /// URL that linked to the initial view of the page
        var referrer: String?

        /// URL of the view
        var url: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case referrer = "referrer"
            case url = "url"
        }
    }
}

/// Schema of all properties of an Action event
internal struct RUMActionEvent: RUMDataModel {
    /// Internal properties
    let dd: DD

    /// Action properties
    let action: Action

    /// Application properties
    let application: Application

    /// Device connectivity properties
    let connectivity: RUMConnectivity?

    /// Start of the event in ms from epoch
    let date: Int64

    /// The service name for this application
    let service: String?

    /// Session properties
    let session: Session

    /// RUM event type
    let type: String = "action"

    /// User properties
    let usr: RUMUser?

    /// View properties
    let view: View

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case action = "action"
        case application = "application"
        case connectivity = "connectivity"
        case date = "date"
        case service = "service"
        case session = "session"
        case type = "type"
        case usr = "usr"
        case view = "view"
    }

    /// Internal properties
    internal struct DD: Codable {
        /// Version of the RUM event format
        let formatVersion: Int64 = 2

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
        }
    }

    /// Action properties
    internal struct Action: Codable {
        /// Properties of the crashes of the action
        let crash: Crash?

        /// Properties of the errors of the action
        let error: Error?

        /// UUID of the action
        let id: String?

        /// Duration in ns to the action is considered loaded
        let loadingTime: Int64?

        /// Properties of the long tasks of the action
        let longTask: LongTask?

        /// Properties of the resources of the action
        let resource: Resource?

        /// Action target properties
        let target: Target?

        /// Type of the action
        let type: ActionType

        enum CodingKeys: String, CodingKey {
            case crash = "crash"
            case error = "error"
            case id = "id"
            case loadingTime = "loading_time"
            case longTask = "long_task"
            case resource = "resource"
            case target = "target"
            case type = "type"
        }

        /// Properties of the crashes of the action
        internal struct Crash: Codable {
            /// Number of crashes that occurred on the action
            let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the errors of the action
        internal struct Error: Codable {
            /// Number of errors that occurred on the action
            let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the long tasks of the action
        internal struct LongTask: Codable {
            /// Number of long tasks that occurred on the action
            let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Properties of the resources of the action
        internal struct Resource: Codable {
            /// Number of resources that occurred on the action
            let count: Int64

            enum CodingKeys: String, CodingKey {
                case count = "count"
            }
        }

        /// Action target properties
        internal struct Target: Codable {
            /// Target name
            var name: String

            enum CodingKeys: String, CodingKey {
                case name = "name"
            }
        }

        /// Type of the action
        internal enum ActionType: String, Codable {
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
    internal struct Application: Codable {
        /// UUID of the application
        let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Session properties
    internal struct Session: Codable {
        /// UUID of the session
        let id: String

        /// Type of the session
        let type: SessionType

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case type = "type"
        }

        /// Type of the session
        internal enum SessionType: String, Codable {
            case user = "user"
            case synthetics = "synthetics"
        }
    }

    /// View properties
    internal struct View: Codable {
        /// UUID of the view
        let id: String

        /// URL that linked to the initial view of the page
        var referrer: String?

        /// URL of the view
        var url: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case referrer = "referrer"
            case url = "url"
        }
    }
}

/// Schema of all properties of an Error event
internal struct RUMErrorEvent: RUMDataModel {
    /// Internal properties
    let dd: DD

    /// Action properties
    let action: Action?

    /// Application properties
    let application: Application

    /// Device connectivity properties
    let connectivity: RUMConnectivity?

    /// Start of the event in ms from epoch
    let date: Int64

    /// Error properties
    let error: Error

    /// The service name for this application
    let service: String?

    /// Session properties
    let session: Session

    /// RUM event type
    let type: String = "error"

    /// User properties
    let usr: RUMUser?

    /// View properties
    let view: View

    enum CodingKeys: String, CodingKey {
        case dd = "_dd"
        case action = "action"
        case application = "application"
        case connectivity = "connectivity"
        case date = "date"
        case error = "error"
        case service = "service"
        case session = "session"
        case type = "type"
        case usr = "usr"
        case view = "view"
    }

    /// Internal properties
    internal struct DD: Codable {
        /// Version of the RUM event format
        let formatVersion: Int64 = 2

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
        }
    }

    /// Action properties
    internal struct Action: Codable {
        /// UUID of the action
        let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Application properties
    internal struct Application: Codable {
        /// UUID of the application
        let id: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
        }
    }

    /// Error properties
    internal struct Error: Codable {
        /// Whether this error crashed the host application
        let isCrash: Bool?

        /// Error message
        var message: String

        /// Resource properties of the error
        let resource: Resource?

        /// Source of the error
        let source: Source

        /// Stacktrace of the error
        var stack: String?

        enum CodingKeys: String, CodingKey {
            case isCrash = "is_crash"
            case message = "message"
            case resource = "resource"
            case source = "source"
            case stack = "stack"
        }

        /// Resource properties of the error
        internal struct Resource: Codable {
            /// HTTP method of the resource
            let method: RUMMethod

            /// The provider for this resource
            let provider: Provider?

            /// HTTP Status code of the resource
            let statusCode: Int64

            /// URL of the resource
            var url: String

            enum CodingKeys: String, CodingKey {
                case method = "method"
                case provider = "provider"
                case statusCode = "status_code"
                case url = "url"
            }

            /// The provider for this resource
            internal struct Provider: Codable {
                /// The domain name of the provider
                let domain: String?

                /// The user friendly name of the provider
                let name: String?

                /// The type of provider
                let type: ProviderType?

                enum CodingKeys: String, CodingKey {
                    case domain = "domain"
                    case name = "name"
                    case type = "type"
                }

                /// The type of provider
                internal enum ProviderType: String, Codable {
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
        internal enum Source: String, Codable {
            case network = "network"
            case source = "source"
            case console = "console"
            case logger = "logger"
            case agent = "agent"
            case webview = "webview"
            case custom = "custom"
        }
    }

    /// Session properties
    internal struct Session: Codable {
        /// UUID of the session
        let id: String

        /// Type of the session
        let type: SessionType

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case type = "type"
        }

        /// Type of the session
        internal enum SessionType: String, Codable {
            case user = "user"
            case synthetics = "synthetics"
        }
    }

    /// View properties
    internal struct View: Codable {
        /// UUID of the view
        let id: String

        /// URL that linked to the initial view of the page
        var referrer: String?

        /// URL of the view
        var url: String

        enum CodingKeys: String, CodingKey {
            case id = "id"
            case referrer = "referrer"
            case url = "url"
        }
    }
}

/// Device connectivity properties
internal struct RUMConnectivity: Codable {
    /// Cellular connectivity properties
    let cellular: Cellular?

    /// The list of available network interfaces
    let interfaces: [Interfaces]

    /// Status of the device connectivity
    let status: Status

    enum CodingKeys: String, CodingKey {
        case cellular = "cellular"
        case interfaces = "interfaces"
        case status = "status"
    }

    /// Cellular connectivity properties
    internal struct Cellular: Codable {
        /// The name of the SIM carrier
        let carrierName: String?

        /// The type of a radio technology used for cellular connection
        let technology: String?

        enum CodingKeys: String, CodingKey {
            case carrierName = "carrier_name"
            case technology = "technology"
        }
    }

    internal enum Interfaces: String, Codable {
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
    internal enum Status: String, Codable {
        case connected = "connected"
        case notConnected = "not_connected"
        case maybe = "maybe"
    }
}

/// User properties
internal struct RUMUser: Codable {
    /// Email of the user
    let email: String?

    /// Identifier of the user
    let id: String?

    /// Name of the user
    let name: String?

    enum CodingKeys: String, CodingKey {
        case email = "email"
        case id = "id"
        case name = "name"
    }
}

/// HTTP method of the resource
internal enum RUMMethod: String, Codable {
    case post = "POST"
    case get = "GET"
    case head = "HEAD"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

// Generated from https://github.com/DataDog/rum-events-format/tree/5c673c12f2fc464ec87dcb5e3a79b0f739a311b7
