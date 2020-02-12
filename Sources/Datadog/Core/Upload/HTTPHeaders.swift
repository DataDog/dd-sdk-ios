import Foundation

/// HTTP headers associated with requests send by SDK.
internal struct HTTPHeaders {
    private struct Constants {
        static let contentTypeField = "Content-Type"
        static let contentTypeValue = "application/json"
        static let userAgentField = "User-Agent"
    }

    let all: [String: String]

    init(appContext: AppContext) {
        // When running on mobile, `User-Agent` header is customized (e.x. `app-name/1 (iPhone; iOS/13.3)`).
        // Other platforms will fall back to default UA header set by OS.
        if let mobileDevice = appContext.mobileDevice {
            let appName = appContext.executableName ?? "Datadog"
            let appVersion = appContext.bundleVersion ?? sdkVersion
            let device = mobileDevice

            self.all = [
                Constants.contentTypeField: Constants.contentTypeValue,
                Constants.userAgentField: "\(appName)/\(appVersion) (\(device.model); \(device.osName)/\(device.osVersion))"
            ]
        } else {
            self.all = [
                Constants.contentTypeField: Constants.contentTypeValue
            ]
        }
    }
}
