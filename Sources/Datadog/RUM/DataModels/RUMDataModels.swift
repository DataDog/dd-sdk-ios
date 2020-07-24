/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

// This file was generated from JSON Schema using quicktype, do not modify it directly.

// MARK: - RUMAction

import Foundation

internal protocol RUMDataModel: Codable { }

/// Schema of all properties of an Action event
///
/// Schema of common properties of RUM events
internal struct RUMAction: RUMDataModel {
    /// Start of the event in ms from epoch
    let date: Int64
    /// Application properties
    let application: RUMApplication
    /// Session properties
    let session: RUMSession
    /// View properties
    let view: RUMActionView
    /// User properties
    let usr: RUMUSR?
    /// Device connectivity properties
    let connectivity: RUMConnectivity?
    /// Internal properties
    let dd: RUMActionDD
    /// RUM event type
    let type = "action"
    /// Action properties
    let action: RUMActionAction

    enum CodingKeys: String, CodingKey {
        case date = "date"
        case application = "application"
        case session = "session"
        case view = "view"
        case usr = "usr"
        case connectivity = "connectivity"
        case dd = "_dd"
        case type = "type"
        case action = "action"
    }
}

// MARK: - RUMActionAction

/// Action properties
internal struct RUMActionAction: Codable {
    /// Type of the action
    let type: RUMActionType
    /// UUID of the action
    let id: String?
    /// Duration in ns to the action is considered loaded
    let loadingTime: Int64?
    /// Action target properties
    let target: RUMTarget?
    /// Properties of the errors of the action
    let error: RUMActionError?
    /// Properties of the crashes of the action
    let crash: RUMActionCrash?
    /// Properties of the long tasks of the action
    let longTask: RUMActionLongTask?
    /// Properties of the resources of the action
    let resource: RUMActionResource?

    enum CodingKeys: String, CodingKey {
        case type = "type"
        case id = "id"
        case loadingTime = "loading_time"
        case target = "target"
        case error = "error"
        case crash = "crash"
        case longTask = "long_task"
        case resource = "resource"
    }
}

// MARK: - RUMActionCrash

/// Properties of the crashes of the action
internal struct RUMActionCrash: Codable {
    /// Number of crashes that occurred on the action
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMActionError

/// Properties of the errors of the action
internal struct RUMActionError: Codable {
    /// Number of errors that occurred on the action
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMActionLongTask

/// Properties of the long tasks of the action
internal struct RUMActionLongTask: Codable {
    /// Number of long tasks that occurred on the action
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMActionResource

/// Properties of the resources of the action
internal struct RUMActionResource: Codable {
    /// Number of resources that occurred on the action
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMTarget

/// Action target properties
internal struct RUMTarget: Codable {
    /// Target name
    let name: String

    enum CodingKeys: String, CodingKey {
        case name = "name"
    }
}

/// Type of the action
internal enum RUMActionType: String, Codable {
    case applicationStart = "application_start"
    case back = "back"
    case click = "click"
    case custom = "custom"
    case scroll = "scroll"
    case swipe = "swipe"
    case tap = "tap"
}

// MARK: - RUMApplication

/// Application properties
internal struct RUMApplication: Codable {
    /// UUID of the application
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
    }
}

// MARK: - RUMConnectivity

/// Device connectivity properties
internal struct RUMConnectivity: Codable {
    /// Status of the device connectivity
    let status: RUMStatus
    /// The list of available network interfaces
    let interfaces: [RUMInterface]
    /// Cellular connectivity properties
    let cellular: RUMCellular?

    enum CodingKeys: String, CodingKey {
        case status = "status"
        case interfaces = "interfaces"
        case cellular = "cellular"
    }
}

// MARK: - RUMCellular

/// Cellular connectivity properties
internal struct RUMCellular: Codable {
    /// The type of a radio technology used for cellular connection
    let technology: String?
    /// The name of the SIM carrier
    let carrierName: String?

    enum CodingKeys: String, CodingKey {
        case technology = "technology"
        case carrierName = "carrier_name"
    }
}

internal enum RUMInterface: String, Codable {
    case bluetooth = "bluetooth"
    case cellular = "cellular"
    case ethernet = "ethernet"
    case mixed = "mixed"
    case none = "none"
    case other = "other"
    case unknown = "unknown"
    case wifi = "wifi"
    case wimax = "wimax"
}

/// Status of the device connectivity
internal enum RUMStatus: String, Codable {
    case connected = "connected"
    case maybe = "maybe"
    case notConnected = "not_connected"
}

// MARK: - RUMActionDD

/// Internal properties
internal struct RUMActionDD: Codable {
    /// Version of the RUM event format
    let formatVersion = 2

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
    }
}

// MARK: - RUMSession

/// Session properties
internal struct RUMSession: Codable {
    /// UUID of the session
    let id: String
    /// Type of the session
    let type: RUMSessionType

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case type = "type"
    }
}

/// Type of the session
internal enum RUMSessionType: String, Codable {
    case synthetics = "synthetics"
    case user = "user"
}

// MARK: - RUMUSR

/// User properties
internal struct RUMUSR: Codable {
    /// Identifier of the user
    let id: String?
    /// Name of the user
    let name: String?
    /// Email of the user
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case name = "name"
        case email = "email"
    }
}

// MARK: - RUMActionView

/// View properties
internal struct RUMActionView: Codable {
    /// UUID of the view
    let id: String
    /// URL that linked to the initial view of the page
    let referrer: String?
    /// URL of the view
    let url: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case referrer = "referrer"
        case url = "url"
    }
}

// MARK: - RUMError

/// Schema of all properties of an Error event
///
/// Schema of common properties of RUM events
internal struct RUMError: RUMDataModel {
    /// Start of the event in ms from epoch
    let date: Int64
    /// Application properties
    let application: RUMApplication
    /// Session properties
    let session: RUMSession
    /// View properties
    let view: RUMActionView
    /// User properties
    let usr: RUMUSR?
    /// Device connectivity properties
    let connectivity: RUMConnectivity?
    /// Internal properties
    let dd: RUMActionDD
    /// RUM event type
    let type = "error"
    /// Error properties
    let error: RUMErrorError
    /// Action properties
    let action: RUMErrorAction?

    enum CodingKeys: String, CodingKey {
        case date = "date"
        case application = "application"
        case session = "session"
        case view = "view"
        case usr = "usr"
        case connectivity = "connectivity"
        case dd = "_dd"
        case type = "type"
        case error = "error"
        case action = "action"
    }
}

// MARK: - RUMErrorAction

/// Action properties
internal struct RUMErrorAction: Codable {
    /// UUID of the action
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
    }
}

// MARK: - RUMErrorError

/// Error properties
internal struct RUMErrorError: Codable {
    /// Error message
    let message: String
    /// Source of the error
    let source: RUMSource
    /// Stacktrace of the error
    let stack: String?
    /// Whether this error crashed the host application
    let isCrash: Bool?
    /// Resource properties of the error
    let resource: RUMErrorResource?

    enum CodingKeys: String, CodingKey {
        case message = "message"
        case source = "source"
        case stack = "stack"
        case isCrash = "is_crash"
        case resource = "resource"
    }
}

// MARK: - RUMErrorResource

/// Resource properties of the error
internal struct RUMErrorResource: Codable {
    /// HTTP method of the resource
    let method: RUMMethod
    /// HTTP Status code of the resource
    let statusCode: Int64
    /// URL of the resource
    let url: String

    enum CodingKeys: String, CodingKey {
        case method = "method"
        case statusCode = "status_code"
        case url = "url"
    }
}

/// HTTP method of the resource
internal enum RUMMethod: String, Codable {
    case delete = "DELETE"
    case head = "HEAD"
    case methodGET = "GET"
    case patch = "PATCH"
    case post = "POST"
    case put = "PUT"
}

/// Source of the error
internal enum RUMSource: String, Codable {
    case agent = "agent"
    case console = "console"
    case logger = "logger"
    case network = "network"
    case source = "source"
    case webview = "webview"
}

// MARK: - RUMLongTask

/// Schema of all properties of a Long Task event
///
/// Schema of common properties of RUM events
internal struct RUMLongTask: RUMDataModel {
    /// Start of the event in ms from epoch
    let date: Int64
    /// Application properties
    let application: RUMApplication
    /// Session properties
    let session: RUMSession
    /// View properties
    let view: RUMActionView
    /// User properties
    let usr: RUMUSR?
    /// Device connectivity properties
    let connectivity: RUMConnectivity?
    /// Internal properties
    let dd: RUMActionDD
    /// RUM event type
    let type = "long_task"
    /// Long Task properties
    let longTask: RUMLongTaskLongTask
    /// Action properties
    let action: RUMLongTaskAction?

    enum CodingKeys: String, CodingKey {
        case date = "date"
        case application = "application"
        case session = "session"
        case view = "view"
        case usr = "usr"
        case connectivity = "connectivity"
        case dd = "_dd"
        case type = "type"
        case longTask = "long_task"
        case action = "action"
    }
}

// MARK: - RUMLongTaskAction

/// Action properties
internal struct RUMLongTaskAction: Codable {
    /// UUID of the action
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
    }
}

// MARK: - RUMLongTaskLongTask

/// Long Task properties
internal struct RUMLongTaskLongTask: Codable {
    /// Duration in ns of the long task
    let duration: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
    }
}

// MARK: - RUMResource

/// Schema of all properties of a Resource event
///
/// Schema of common properties of RUM events
internal struct RUMResource: RUMDataModel {
    /// Start of the event in ms from epoch
    let date: Int64
    /// Application properties
    let application: RUMApplication
    /// Session properties
    let session: RUMSession
    /// View properties
    let view: RUMActionView
    /// User properties
    let usr: RUMUSR?
    /// Device connectivity properties
    let connectivity: RUMConnectivity?
    /// Internal properties
    let dd: RUMActionDD
    /// RUM event type
    let type = "resource"
    /// Resource properties
    let resource: RUMResourceResource
    /// Action properties
    let action: RUMResourceAction?

    enum CodingKeys: String, CodingKey {
        case date = "date"
        case application = "application"
        case session = "session"
        case view = "view"
        case usr = "usr"
        case connectivity = "connectivity"
        case dd = "_dd"
        case type = "type"
        case resource = "resource"
        case action = "action"
    }
}

// MARK: - RUMResourceAction

/// Action properties
internal struct RUMResourceAction: Codable {
    /// UUID of the action
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
    }
}

// MARK: - RUMResourceResource

/// Resource properties
internal struct RUMResourceResource: Codable {
    /// Resource type
    let type: RUMResourceType
    /// HTTP method of the resource
    let method: RUMMethod?
    /// URL of the resource
    let url: String
    /// HTTP status code of the resource
    let statusCode: Int64?
    /// Duration of the resource
    let duration: Int64
    /// Size in octet of the resource response body
    let size: Int64?
    /// Redirect phase properties
    let redirect: RUMRedirect?
    /// DNS phase properties
    let dns: RUMDNS?
    /// Connect phase properties
    let connect: RUMConnect?
    /// SSL phase properties
    let ssl: RUMSSL?
    /// First Byte phase properties
    let firstByte: RUMFirstByte?
    /// Download phase properties
    let download: RUMDownload?

    enum CodingKeys: String, CodingKey {
        case type = "type"
        case method = "method"
        case url = "url"
        case statusCode = "status_code"
        case duration = "duration"
        case size = "size"
        case redirect = "redirect"
        case dns = "dns"
        case connect = "connect"
        case ssl = "ssl"
        case firstByte = "first_byte"
        case download = "download"
    }
}

// MARK: - RUMConnect

/// Connect phase properties
internal struct RUMConnect: Codable {
    /// Duration in ns of the resource connect phase
    let duration: Int64
    /// Duration in ns between start of the request and start of the connect phase
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
        case start = "start"
    }
}

// MARK: - RUMDNS

/// DNS phase properties
internal struct RUMDNS: Codable {
    /// Duration in ns of the resource dns phase
    let duration: Int64
    /// Duration in ns between start of the request and start of the dns phase
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
        case start = "start"
    }
}

// MARK: - RUMDownload

/// Download phase properties
internal struct RUMDownload: Codable {
    /// Duration in ns of the resource download phase
    let duration: Int64
    /// Duration in ns between start of the request and start of the download phase
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
        case start = "start"
    }
}

// MARK: - RUMFirstByte

/// First Byte phase properties
internal struct RUMFirstByte: Codable {
    /// Duration in ns of the resource first byte phase
    let duration: Int64
    /// Duration in ns between start of the request and start of the first byte phase
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
        case start = "start"
    }
}

// MARK: - RUMRedirect

/// Redirect phase properties
internal struct RUMRedirect: Codable {
    /// Duration in ns of the resource redirect phase
    let duration: Int64
    /// Duration in ns between start of the request and start of the redirect phase
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
        case start = "start"
    }
}

// MARK: - RUMSSL

/// SSL phase properties
internal struct RUMSSL: Codable {
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
internal enum RUMResourceType: String, Codable {
    case beacon = "beacon"
    case css = "css"
    case document = "document"
    case fetch = "fetch"
    case font = "font"
    case image = "image"
    case js = "js"
    case media = "media"
    case other = "other"
    case xhr = "xhr"
}

// MARK: - RUMView

/// Schema of all properties of a View event
///
/// Schema of common properties of RUM events
internal struct RUMView: RUMDataModel {
    /// Start of the event in ms from epoch
    let date: Int64
    /// Application properties
    let application: RUMApplication
    /// Session properties
    let session: RUMSession
    /// View properties
    let view: RUMViewView
    /// User properties
    let usr: RUMUSR?
    /// Device connectivity properties
    let connectivity: RUMConnectivity?
    /// Internal properties
    let dd: RUMViewDD
    /// RUM event type
    let type = "view"

    enum CodingKeys: String, CodingKey {
        case date = "date"
        case application = "application"
        case session = "session"
        case view = "view"
        case usr = "usr"
        case connectivity = "connectivity"
        case dd = "_dd"
        case type = "type"
    }
}

// MARK: - RUMViewDD

/// Internal properties
internal struct RUMViewDD: Codable {
    /// Version of the RUM event format
    let formatVersion = 2
    /// Version of the update of the view event
    let documentVersion: Int64

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case documentVersion = "document_version"
    }
}

// MARK: - RUMViewView

/// View properties
internal struct RUMViewView: Codable {
    /// UUID of the view
    let id: String
    /// URL that linked to the initial view of the page
    let referrer: String?
    /// URL of the view
    let url: String
    /// Duration in ns to the view is considered loaded
    let loadingTime: Int64?
    /// Type of the loading of the view
    let loadingType: RUMLoadingType?
    /// Time spent on the view in ns
    let timeSpent: Int64
    /// Duration in ns to the first rendering
    let firstContentfulPaint: Int64?
    /// Duration in ns to the complete parsing and loading of the document and its sub resources
    let domComplete: Int64?
    /// Duration in ns to the complete parsing and loading of the document without its sub
    /// resources
    let domContentLoaded: Int64?
    /// Duration in ns to the end of the parsing of the document
    let domInteractive: Int64?
    /// Duration in ns to the end of the load event handler execution
    let loadEvent: Int64?
    /// Properties of the actions of the view
    let action: RUMViewAction
    /// Properties of the errors of the view
    let error: RUMViewError
    /// Properties of the crashes of the view
    let crash: RUMViewCrash?
    /// Properties of the long tasks of the view
    let longTask: RUMViewLongTask?
    /// Properties of the resources of the view
    let resource: RUMViewResource

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case referrer = "referrer"
        case url = "url"
        case loadingTime = "loading_time"
        case loadingType = "loading_type"
        case timeSpent = "time_spent"
        case firstContentfulPaint = "first_contentful_paint"
        case domComplete = "dom_complete"
        case domContentLoaded = "dom_content_loaded"
        case domInteractive = "dom_interactive"
        case loadEvent = "load_event"
        case action = "action"
        case error = "error"
        case crash = "crash"
        case longTask = "long_task"
        case resource = "resource"
    }
}

// MARK: - RUMViewAction

/// Properties of the actions of the view
internal struct RUMViewAction: Codable {
    /// Number of actions that occurred on the view
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMViewCrash

/// Properties of the crashes of the view
internal struct RUMViewCrash: Codable {
    /// Number of crashes that occurred on the view
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMViewError

/// Properties of the errors of the view
internal struct RUMViewError: Codable {
    /// Number of errors that occurred on the view
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

/// Type of the loading of the view
internal enum RUMLoadingType: String, Codable {
    case activityDisplay = "activity_display"
    case activityRedisplay = "activity_redisplay"
    case fragmentDisplay = "fragment_display"
    case fragmentRedisplay = "fragment_redisplay"
    case initialLoad = "initial_load"
    case routeChange = "route_change"
}

// MARK: - RUMViewLongTask

/// Properties of the long tasks of the view
internal struct RUMViewLongTask: Codable {
    /// Number of long tasks that occurred on the view
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMViewResource

/// Properties of the resources of the view
internal struct RUMViewResource: Codable {
    /// Number of resources that occurred on the view
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}
// b6eb2bf04511aa22db9b73ba0d195ee9c365bee7
