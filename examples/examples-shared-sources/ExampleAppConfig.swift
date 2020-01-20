import Foundation

/// Basic configuration to read your Datadog client token from `examples-secret.xcconfig`.
struct ExampleAppConfig {
    let clientToken: String

    init() {
        guard let clientToken = Bundle.main.infoDictionary?["DatadogClientToken"] as? String, !clientToken.isEmpty else {
            // If you see this error when running example app it means your `examples-secret.xcconfig` file is
            // missing or missconfigured. Please refer to `README.md` file in SDK's repository root folder
            // to create it.
            fatalError("""
            ✋⛔️ Cannot read `DATADOG_CLIENT_TOKEN` from `Info.plist` dictionary.
            See your configuration of `examples-secret.xcconfig` or refer to `README.md` if you haven't created this file yet.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }

        self.clientToken = clientToken
    }
}
