import UIKit
import Datadog

fileprivate(set) var logger: Logger!

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    private lazy var config = ExampleAppConfig()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Initialize Datadog SDK
        Datadog.initialize(
            endpointURL: "https://mobile-http-intake.logs.datadoghq.com/v1/input/",
            clientToken: config.clientToken // use your own client token obtained on Datadog website
        )

        // Create logger instance
        logger = Logger.builder
            .set(serviceName: "ios-sdk-test-service")
            .printLogsToConsole(true, usingFormat: .short)
            .build()

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}
