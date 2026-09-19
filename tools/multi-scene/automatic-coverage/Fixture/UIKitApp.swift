import UIKit

@main final class UIKitApp: UIResponder, UIApplicationDelegate {
    func application(_ app: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FixtureObservation.start(); return true
    }
}
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene); self.window = window
        if Settings.layout == "split" {
            let split = UISplitViewController(style: .doubleColumn)
            split.preferredDisplayMode = .oneBesideSecondary
            split.setViewController(UINavigationController(rootViewController: SidebarController()), for: .primary)
            split.setViewController(UINavigationController(rootViewController: EmptyController()), for: .secondary)
            window.rootViewController = split
        } else { window.rootViewController = UINavigationController(rootViewController: HomeController()) }
        window.makeKeyAndVisible()
    }
}
class SurfaceController: UIViewController, UIScrollViewDelegate {
    var screen: String { "surface" }
    var count = 0
    let receipt = UILabel()
    let controls = UIStackView()
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground; title = screen.capitalized
        controls.axis = .vertical; controls.spacing = 8; controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        NSLayoutConstraint.activate([controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)])
        let heading = UILabel(); heading.text = screen; heading.accessibilityIdentifier = "screen." + screen
        controls.addArrangedSubview(heading)
        button("Tap", "tap") { [weak self] in self?.count += 1; self?.refresh() }
        addNavigation()
        let toggle = UISwitch(); toggle.accessibilityIdentifier = screen + ".toggle"
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged); controls.addArrangedSubview(toggle)
        let scroll = UIScrollView(); scroll.accessibilityIdentifier = screen + ".scroll"; scroll.delegate = self
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        let rows = UIStackView(); rows.axis = .vertical; rows.spacing = 6; rows.translatesAutoresizingMaskIntoConstraints = false
        for i in 0..<30 { let l = UILabel(); l.text = "Row \(i)"; l.heightAnchor.constraint(equalToConstant: 30).isActive = true; rows.addArrangedSubview(l) }
        scroll.addSubview(rows)
        NSLayoutConstraint.activate([rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
        controls.addArrangedSubview(scroll)
        receipt.accessibilityIdentifier = screen + ".receipt"; controls.addArrangedSubview(receipt); refresh()
    }
    func refresh() { receipt.text = "receipt:\(count)" }
    func addNavigation() {}
    func button(_ title: String, _ name: String, action: @escaping () -> Void) {
        let b = UIButton(type: .system); b.setTitle(title, for: .normal); b.accessibilityIdentifier = screen + "." + name
        b.heightAnchor.constraint(equalToConstant: 38).isActive = true
        b.addAction(UIAction { [weak self] _ in FixtureObservation.hit((self?.screen ?? "missing") + "." + name); action() }, for: .touchUpInside)
        controls.addArrangedSubview(b)
    }
    @objc func toggled() { FixtureObservation.hit(screen + ".toggle"); count += 1; refresh() }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); FixtureObservation.appeared(screen) }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        ObservationStore.shared.append("native_scroll", ["screen": screen, "offset": scrollView.contentOffset.y, "decelerating": decelerate])
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        ObservationStore.shared.append("native_scroll_end", ["screen": screen, "offset": scrollView.contentOffset.y])
    }
}
final class HomeController: SurfaceController {
    override var screen: String { "home" }
    override func addNavigation() { button("Open detail", "next") { [weak self] in self?.navigationController?.pushViewController(DetailController(), animated: true) } }
}
final class SidebarController: SurfaceController {
    override var screen: String { "sidebar" }
    override func addNavigation() {
        button("Open detail", "next") { [weak self] in
            let nav = UINavigationController(rootViewController: DetailController())
            self?.splitViewController?.setViewController(nav, for: .secondary)
            self?.splitViewController?.show(.secondary)
        }
    }
}
final class EmptyController: SurfaceController { override var screen: String { "empty" } }
final class DetailController: SurfaceController {
    override var screen: String { "detail" }
    override func addNavigation() {
        button("Present sheet", "sheet") { [weak self] in self?.present(SheetController(), animated: true) }
        button("Return home", "back") { [weak self] in
            if let split = self?.splitViewController {
                split.setViewController(UINavigationController(rootViewController: EmptyController()), for: .secondary); split.show(.primary)
            } else { self?.navigationController?.popViewController(animated: true) }
        }
    }
}
final class SheetController: SurfaceController {
    override var screen: String { "sheet" }
    override func addNavigation() { button("Dismiss sheet", "close") { [weak self] in self?.dismiss(animated: true) } }
}
