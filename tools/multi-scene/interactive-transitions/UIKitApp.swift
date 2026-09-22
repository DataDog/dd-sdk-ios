import UIKit

@main final class UIKitApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FixtureObservation.start(); return true
    }
}
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        if Settings.layout == "split" {
            let split = UISplitViewController(style: .doubleColumn)
            split.preferredDisplayMode = .oneBesideSecondary
            split.setViewController(UINavigationController(rootViewController: SidebarController()), for: .primary)
            split.setViewController(UINavigationController(rootViewController: EmptyController()), for: .secondary)
            window.rootViewController = split
        } else { window.rootViewController = UINavigationController(rootViewController: HomeController()) }
        self.window = window; window.makeKeyAndVisible()
    }
}
class SurfaceController: UIViewController {
    var screen: String { "surface" }
    private let controls = UIStackView()
    override func viewDidLoad() {
        super.viewDidLoad(); title = screen.capitalized; view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "controller." + screen
        controls.axis = .vertical; controls.spacing = 20; controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 36)
        ])
        let heading = UILabel(); heading.text = screen; heading.accessibilityIdentifier = "screen." + screen
        controls.addArrangedSubview(heading); navigationControls()
    }
    func navigationControls() {}
    func button(_ title: String, _ key: String, _ action: @escaping () -> Void) {
        let button = UIButton(type: .system); button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = screen + "." + key
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        button.addAction(UIAction { [weak self] _ in
            FixtureObservation.hit((self?.screen ?? "nil") + "." + key); action()
        }, for: .touchUpInside)
        controls.addArrangedSubview(button)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); FixtureObservation.appeared(screen)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); FixtureObservation.disappeared(screen)
    }
}
final class HomeController: SurfaceController {
    override var screen: String { "home" }
    override func navigationControls() {
        button("Open detail", "next") { [weak self] in
            self?.navigationController?.pushViewController(DetailController(), animated: true)
        }
    }
}
final class SidebarController: SurfaceController {
    override var screen: String { "sidebar" }
    override func navigationControls() {
        button("Open detail", "next") { [weak self] in
            let detail = DetailController()
            TransitionModel.select("detail", occurrence: UUID().uuidString.lowercased())
            self?.splitViewController?.setViewController(UINavigationController(rootViewController: detail), for: .secondary)
            self?.splitViewController?.show(.secondary)
        }
    }
}
final class EmptyController: SurfaceController { override var screen: String { "empty" } }
final class DetailController: SurfaceController {
    override var screen: String { "detail" }
    override func navigationControls() {
        button("Present sheet", "sheet") { [weak self] in
            let sheet = SheetController(); sheet.modalPresentationStyle = .pageSheet
            self?.present(sheet, animated: true)
        }
        button("Return home", "back") { [weak self] in
            if let split = self?.splitViewController {
                TransitionModel.select(nil, occurrence: nil)
                split.setViewController(UINavigationController(rootViewController: EmptyController()), for: .secondary)
                split.show(.primary)
            } else { self?.navigationController?.popViewController(animated: true) }
        }
    }
}
final class SheetController: SurfaceController {
    override var screen: String { "sheet" }
    override func navigationControls() {
        button("Dismiss sheet", "close") { [weak self] in self?.dismiss(animated: true) }
    }
}
