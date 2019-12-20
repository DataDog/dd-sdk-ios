import Foundation

/// Basic configuration to read your Datadog API configuration from `dd-config.plist` file.
struct ExampleAppConfig {
    let clientToken: String

    init() {
        guard
            let url = Bundle.main.url(forResource: "dd-config.plist", withExtension: nil),
            let config = NSDictionary(contentsOf: url),
            let clientToken = config["clientToken"] as? String
        else {
            // If you see this error when running example app it means your `dd-config.plist` file is not
            // properly configured. Please refer to `README.md` file in SDK's repository root folder
            // to create it.
            fatalError("Correct `dd-config.plist` file was not found in app installation directory.")
        }

        self.clientToken = clientToken
    }
}
