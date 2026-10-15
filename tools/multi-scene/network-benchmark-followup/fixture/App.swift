import UIKit
@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = Scene.self
        return configuration
    }
}
final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene); let controller = UIViewController()
        controller.view.backgroundColor = .white; window.rootViewController = controller; self.window = window; window.makeKeyAndVisible()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { E01Fixture().run() }
    }
}
