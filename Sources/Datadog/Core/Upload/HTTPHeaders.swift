import Foundation

internal protocol HTTPHeader {
    var field: String { get }
    var value: String { get }
}

/// HTTP headers associated with requests send by SDK.
internal struct HTTPHeaders {
    let all: [String: String]

    init(appContext: AppContext) {
        var headers: [HTTPHeader] = [ContentTypeHeader()]

        // When running on mobile, `User-Agent` header is customized.
        // Other platforms will fall back to default UA header set by OS.
        if let mobileDevice = appContext.mobileDevice {
            headers.append(
                MobileDeviceUserAgentHeader(
                    appName: appContext.executableName ?? "Datadog",
                    appVersion: appContext.bundleVersion ?? sdkVersion,
                    device: mobileDevice
                )
            )
        }

        self.all = Dictionary(uniqueKeysWithValues: headers.map { ($0.field, $0.value) })
    }
}

internal struct ContentTypeHeader: HTTPHeader {
    let field = "Content-Type"
    let value = "application/json"
}

internal struct MobileDeviceUserAgentHeader: HTTPHeader {
    let field = "User-Agent"
    let value: String

    init(appName: String, appVersion: String, device: MobileDevice) {
        // Example: `app-name/1 (iPhone; iOS/13.3)`
        self.value = "\(appName)/\(appVersion) (\(device.model); \(device.osName)/\(device.osVersion))"
    }
}
