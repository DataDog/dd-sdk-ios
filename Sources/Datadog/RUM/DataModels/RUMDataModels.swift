/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

// This file was generated from JSON Schema using quicktype, do not modify it directly.

// MARK: - RUMDataAction

import Foundation

internal protocol RUMDataModel: Codable { }

/// Schema of all properties of an Action event
///
/// Schema of common properties of RUM events
internal struct RUMDataAction: RUMDataModel {
    /// Start of the event in ms from epoch
    let date: Int64
    /// Application properties
    let application: RUMDataApplication
    /// The service name for this application
    let service: String?
    /// Session properties
    let session: RUMDataSession
    /// View properties
    let view: RUMDataActionView
    /// User properties
    let usr: RUMDataUSR?
    /// Device connectivity properties
    let connectivity: RUMDataConnectivity?
    /// Internal properties
    let dd: RUMDataActionDD
    /// RUM event type
    let type = "action"
    /// Action properties
    let action: RUMDataActionAction

    enum CodingKeys: String, CodingKey {
        case date = "date"
        case application = "application"
        case service = "service"
        case session = "session"
        case view = "view"
        case usr = "usr"
        case connectivity = "connectivity"
        case dd = "_dd"
        case type = "type"
        case action = "action"
    }
}

// MARK: - RUMDataActionAction

/// Action properties
internal struct RUMDataActionAction: Codable {
    /// Type of the action
    let type: RUMDataActionType
    /// UUID of the action
    let id: String?
    /// Duration in ns to the action is considered loaded
    let loadingTime: Int64?
    /// Action target properties
    let target: RUMDataTarget?
    /// Properties of the errors of the action
    let error: RUMDataActionError?
    /// Properties of the crashes of the action
    let crash: RUMDataActionCrash?
    /// Properties of the long tasks of the action
    let longTask: RUMDataActionLongTask?
    /// Properties of the resources of the action
    let resource: RUMDataActionResource?

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

// MARK: - RUMDataActionCrash

/// Properties of the crashes of the action
internal struct RUMDataActionCrash: Codable {
    /// Number of crashes that occurred on the action
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMDataActionError

/// Properties of the errors of the action
internal struct RUMDataActionError: Codable {
    /// Number of errors that occurred on the action
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMDataActionLongTask

/// Properties of the long tasks of the action
internal struct RUMDataActionLongTask: Codable {
    /// Number of long tasks that occurred on the action
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMDataActionResource

/// Properties of the resources of the action
internal struct RUMDataActionResource: Codable {
    /// Number of resources that occurred on the action
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMDataTarget

/// Action target properties
internal struct RUMDataTarget: Codable {
    /// Target name
    let name: String

    enum CodingKeys: String, CodingKey {
        case name = "name"
    }
}

/// Type of the action
internal enum RUMDataActionType: String, Codable {
    case applicationStart = "application_start"
    case back = "back"
    case click = "click"
    case custom = "custom"
    case scroll = "scroll"
    case swipe = "swipe"
    case tap = "tap"
}

// MARK: - RUMDataApplication

/// Application properties
internal struct RUMDataApplication: Codable {
    /// UUID of the application
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
    }
}

// MARK: - RUMDataConnectivity

/// Device connectivity properties
internal struct RUMDataConnectivity: Codable {
    /// Status of the device connectivity
    let status: RUMDataStatus
    /// The list of available network interfaces
    let interfaces: [RUMDataInterface]
    /// Cellular connectivity properties
    let cellular: RUMDataCellular?

    enum CodingKeys: String, CodingKey {
        case status = "status"
        case interfaces = "interfaces"
        case cellular = "cellular"
    }
}

// MARK: - RUMDataCellular

/// Cellular connectivity properties
internal struct RUMDataCellular: Codable {
    /// The type of a radio technology used for cellular connection
    let technology: String?
    /// The name of the SIM carrier
    let carrierName: String?

    enum CodingKeys: String, CodingKey {
        case technology = "technology"
        case carrierName = "carrier_name"
    }
}

internal enum RUMDataInterface: String, Codable {
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
internal enum RUMDataStatus: String, Codable {
    case connected = "connected"
    case maybe = "maybe"
    case notConnected = "not_connected"
}

// MARK: - RUMDataActionDD

/// Internal properties
internal struct RUMDataActionDD: Codable {
    /// Version of the RUM event format
    let formatVersion = 2

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
    }
}

// MARK: - RUMDataSession

/// Session properties
internal struct RUMDataSession: Codable {
    /// UUID of the session
    let id: String
    /// Type of the session
    let type: RUMDataSessionType

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case type = "type"
    }
}

/// Type of the session
internal enum RUMDataSessionType: String, Codable {
    case synthetics = "synthetics"
    case user = "user"
}

// MARK: - RUMDataUSR

/// User properties
internal struct RUMDataUSR: Codable {
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

// MARK: - RUMDataActionView

/// View properties
internal struct RUMDataActionView: Codable {
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

// MARK: - RUMDataError

/// Schema of all properties of an Error event
///
/// Schema of common properties of RUM events
internal struct RUMDataError: RUMDataModel {
    /// Start of the event in ms from epoch
    let date: Int64
    /// Application properties
    let application: RUMDataApplication
    /// The service name for this application
    let service: String?
    /// Session properties
    let session: RUMDataSession
    /// View properties
    let view: RUMDataActionView
    /// User properties
    let usr: RUMDataUSR?
    /// Device connectivity properties
    let connectivity: RUMDataConnectivity?
    /// Internal properties
    let dd: RUMDataActionDD
    /// RUM event type
    let type = "error"
    /// Error properties
    let error: RUMDataErrorError
    /// Action properties
    let action: RUMDataErrorAction?

    enum CodingKeys: String, CodingKey {
        case date = "date"
        case application = "application"
        case service = "service"
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

// MARK: - RUMDataErrorAction

/// Action properties
internal struct RUMDataErrorAction: Codable {
    /// UUID of the action
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
    }
}

// MARK: - RUMDataErrorError

/// Error properties
internal struct RUMDataErrorError: Codable {
    /// Error message
    let message: String
    /// Source of the error
    let source: RUMDataSource
    /// Stacktrace of the error
    let stack: String?
    /// Whether this error crashed the host application
    let isCrash: Bool?
    /// Resource properties of the error
    let resource: RUMDataErrorResource?

    enum CodingKeys: String, CodingKey {
        case message = "message"
        case source = "source"
        case stack = "stack"
        case isCrash = "is_crash"
        case resource = "resource"
    }
}

// MARK: - RUMDataErrorResource

/// Resource properties of the error
internal struct RUMDataErrorResource: Codable {
    /// HTTP method of the resource
    let method: RUMDataMethod
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
internal enum RUMDataMethod: String, Codable {
    case delete = "DELETE"
    case head = "HEAD"
    case methodGET = "GET"
    case patch = "PATCH"
    case post = "POST"
    case put = "PUT"
}

/// Source of the error
internal enum RUMDataSource: String, Codable {
    case agent = "agent"
    case console = "console"
    case custom = "custom"
    case logger = "logger"
    case network = "network"
    case source = "source"
    case webview = "webview"
}

// MARK: - RUMDataLongTask

/// Schema of all properties of a Long Task event
///
/// Schema of common properties of RUM events
internal struct RUMDataLongTask: RUMDataModel {
    /// Start of the event in ms from epoch
    let date: Int64
    /// Application properties
    let application: RUMDataApplication
    /// The service name for this application
    let service: String?
    /// Session properties
    let session: RUMDataSession
    /// View properties
    let view: RUMDataActionView
    /// User properties
    let usr: RUMDataUSR?
    /// Device connectivity properties
    let connectivity: RUMDataConnectivity?
    /// Internal properties
    let dd: RUMDataActionDD
    /// RUM event type
    let type = "long_task"
    /// Long Task properties
    let longTask: RUMDataLongTaskLongTask
    /// Action properties
    let action: RUMDataLongTaskAction?

    enum CodingKeys: String, CodingKey {
        case date = "date"
        case application = "application"
        case service = "service"
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

// MARK: - RUMDataLongTaskAction

/// Action properties
internal struct RUMDataLongTaskAction: Codable {
    /// UUID of the action
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
    }
}

// MARK: - RUMDataLongTaskLongTask

/// Long Task properties
internal struct RUMDataLongTaskLongTask: Codable {
    /// Duration in ns of the long task
    let duration: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
    }
}

// MARK: - RUMDataResource

/// Schema of all properties of a Resource event
///
/// Schema of common properties of RUM events
internal struct RUMDataResource: RUMDataModel {
    /// Start of the event in ms from epoch
    let date: Int64
    /// Application properties
    let application: RUMDataApplication
    /// The service name for this application
    let service: String?
    /// Session properties
    let session: RUMDataSession
    /// View properties
    let view: RUMDataActionView
    /// User properties
    let usr: RUMDataUSR?
    /// Device connectivity properties
    let connectivity: RUMDataConnectivity?
    /// Internal properties
    let dd: RUMDataResourceDD
    /// RUM event type
    let type = "resource"
    /// Resource properties
    let resource: RUMDataResourceResource
    /// Action properties
    let action: RUMDataResourceAction?

    enum CodingKeys: String, CodingKey {
        case date = "date"
        case application = "application"
        case service = "service"
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

// MARK: - RUMDataResourceAction

/// Action properties
internal struct RUMDataResourceAction: Codable {
    /// UUID of the action
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
    }
}

// MARK: - RUMDataResourceDD

/// Internal properties
internal struct RUMDataResourceDD: Codable {
    /// Version of the RUM event format
    let formatVersion = 2
    /// span identifier in decimal format
    let spanID: String?
    /// trace identifier in decimal format
    let traceID: String?

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case spanID = "span_id"
        case traceID = "trace_id"
    }
}

// MARK: - RUMDataResourceResource

/// Resource properties
internal struct RUMDataResourceResource: Codable {
    /// UUID of the resource
    let id: String?
    /// Resource type
    let type: RUMDataResourceType
    /// HTTP method of the resource
    let method: RUMDataMethod?
    /// URL of the resource
    let url: String
    /// HTTP status code of the resource
    let statusCode: Int64?
    /// Duration of the resource
    let duration: Int64
    /// Size in octet of the resource response body
    let size: Int64?
    /// Redirect phase properties
    let redirect: RUMDataRedirect?
    /// DNS phase properties
    let dns: RUMDataDNS?
    /// Connect phase properties
    let connect: RUMDataConnect?
    /// SSL phase properties
    let ssl: RUMDataSSL?
    /// First Byte phase properties
    let firstByte: RUMDataFirstByte?
    /// Download phase properties
    let download: RUMDataDownload?

    enum CodingKeys: String, CodingKey {
        case id = "id"
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

// MARK: - RUMDataConnect

/// Connect phase properties
internal struct RUMDataConnect: Codable {
    /// Duration in ns of the resource connect phase
    let duration: Int64
    /// Duration in ns between start of the request and start of the connect phase
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
        case start = "start"
    }
}

// MARK: - RUMDataDNS

/// DNS phase properties
internal struct RUMDataDNS: Codable {
    /// Duration in ns of the resource dns phase
    let duration: Int64
    /// Duration in ns between start of the request and start of the dns phase
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
        case start = "start"
    }
}

// MARK: - RUMDataDownload

/// Download phase properties
internal struct RUMDataDownload: Codable {
    /// Duration in ns of the resource download phase
    let duration: Int64
    /// Duration in ns between start of the request and start of the download phase
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
        case start = "start"
    }
}

// MARK: - RUMDataFirstByte

/// First Byte phase properties
internal struct RUMDataFirstByte: Codable {
    /// Duration in ns of the resource first byte phase
    let duration: Int64
    /// Duration in ns between start of the request and start of the first byte phase
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
        case start = "start"
    }
}

// MARK: - RUMDataRedirect

/// Redirect phase properties
internal struct RUMDataRedirect: Codable {
    /// Duration in ns of the resource redirect phase
    let duration: Int64
    /// Duration in ns between start of the request and start of the redirect phase
    let start: Int64

    enum CodingKeys: String, CodingKey {
        case duration = "duration"
        case start = "start"
    }
}

// MARK: - RUMDataSSL

/// SSL phase properties
internal struct RUMDataSSL: Codable {
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
internal enum RUMDataResourceType: String, Codable {
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

// MARK: - RUMDataView

/// Schema of all properties of a View event
///
/// Schema of common properties of RUM events
internal struct RUMDataView: RUMDataModel {
    /// Start of the event in ms from epoch
    let date: Int64
    /// Application properties
    let application: RUMDataApplication
    /// The service name for this application
    let service: String?
    /// Session properties
    let session: RUMDataSession
    /// View properties
    let view: RUMDataViewView
    /// User properties
    let usr: RUMDataUSR?
    /// Device connectivity properties
    let connectivity: RUMDataConnectivity?
    /// Internal properties
    let dd: RUMDataViewDD
    /// RUM event type
    let type = "view"

    enum CodingKeys: String, CodingKey {
        case date = "date"
        case application = "application"
        case service = "service"
        case session = "session"
        case view = "view"
        case usr = "usr"
        case connectivity = "connectivity"
        case dd = "_dd"
        case type = "type"
    }
}

// MARK: - RUMDataViewDD

/// Internal properties
internal struct RUMDataViewDD: Codable {
    /// Version of the RUM event format
    let formatVersion = 2
    /// Version of the update of the view event
    let documentVersion: Int64

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case documentVersion = "document_version"
    }
}

// MARK: - RUMDataViewView

/// View properties
internal struct RUMDataViewView: Codable {
    /// UUID of the view
    let id: String
    /// URL that linked to the initial view of the page
    let referrer: String?
    /// URL of the view
    let url: String
    /// Duration in ns to the view is considered loaded
    let loadingTime: Int64?
    /// Type of the loading of the view
    let loadingType: RUMDataLoadingType?
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
    let action: RUMDataViewAction
    /// Properties of the errors of the view
    let error: RUMDataViewError
    /// Properties of the crashes of the view
    let crash: RUMDataViewCrash?
    /// Properties of the long tasks of the view
    let longTask: RUMDataViewLongTask?
    /// Properties of the resources of the view
    let resource: RUMDataViewResource

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

// MARK: - RUMDataViewAction

/// Properties of the actions of the view
internal struct RUMDataViewAction: Codable {
    /// Number of actions that occurred on the view
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMDataViewCrash

/// Properties of the crashes of the view
internal struct RUMDataViewCrash: Codable {
    /// Number of crashes that occurred on the view
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMDataViewError

/// Properties of the errors of the view
internal struct RUMDataViewError: Codable {
    /// Number of errors that occurred on the view
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

/// Type of the loading of the view
internal enum RUMDataLoadingType: String, Codable {
    case activityDisplay = "activity_display"
    case activityRedisplay = "activity_redisplay"
    case fragmentDisplay = "fragment_display"
    case fragmentRedisplay = "fragment_redisplay"
    case initialLoad = "initial_load"
    case routeChange = "route_change"
    case viewControllerDisplay = "view_controller_display"
    case viewControllerRedisplay = "view_controller_redisplay"
}

// MARK: - RUMDataViewLongTask

/// Properties of the long tasks of the view
internal struct RUMDataViewLongTask: Codable {
    /// Number of long tasks that occurred on the view
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}

// MARK: - RUMDataViewResource

/// Properties of the resources of the view
internal struct RUMDataViewResource: Codable {
    /// Number of resources that occurred on the view
    let count: Int64

    enum CodingKeys: String, CodingKey {
        case count = "count"
    }
}
// 0ae8f253c60662158a1342d8b680243a14d03578
