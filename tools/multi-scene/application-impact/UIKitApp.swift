/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

final class ImpactListController: UITableViewController {
    let screen: String
    init(_ screen: String) { self.screen = screen; super.init(style: .plain); title = screen }
    required init?(coder: NSCoder) { nil }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 150 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "row")
        cell.textLabel?.text = "Item \(indexPath.row)"
        cell.detailTextLabel?.text = "Local deterministic application data"
        cell.imageView?.image = UIImage(systemName: "chart.bar.fill")
        return cell
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ImpactEvidence.shared.record("native-appear", ["screen": screen])
    }
}

@MainActor
final class UIKitJourney: NSObject, ImpactJourney, UINavigationControllerDelegate {
    let home = ImpactListController("home")
    let navigation: UINavigationController
    var root: UIViewController { navigation }
    var shown = ""
    var presented = false
    override init() { navigation = UINavigationController(rootViewController: home); super.init(); navigation.delegate = self }
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        shown = (viewController as? ImpactListController)?.screen ?? "foreign"
        ImpactEvidence.shared.record("native-navigation", ["screen": shown])
    }
    func perform(step: Int, cycle: Int) {
        switch step {
        case 0: home.tableView.scrollToRow(at: IndexPath(row: cycle % 2 == 0 ? 100 : 0, section: 0), at: .top, animated: true)
        case 2: navigation.pushViewController(ImpactListController("detail"), animated: true)
        case 3: (navigation.topViewController as? ImpactListController)?.tableView.scrollToRow(at: IndexPath(row: 100, section: 0), at: .top, animated: true)
        case 4: navigation.present(ImpactListController("sheet"), animated: true) { self.presented = true }
        case 5: (navigation.presentedViewController as? ImpactListController)?.tableView.scrollToRow(at: IndexPath(row: 100, section: 0), at: .top, animated: true)
        case 6: navigation.dismiss(animated: true) { self.presented = false }
        case 7: navigation.popViewController(animated: true)
        default: break
        }
    }
    func verify(step: Int, cycle: Int) -> Bool {
        let sheet = step == 4 || step == 5
        let expected = step < 2 || step == 7 ? "home" : "detail"
        return shown == expected && navigation.transitionCoordinator == nil
            && presented == sheet && (navigation.presentedViewController != nil) == sheet
            && navigation.viewControllers.count == (expected == "home" ? 1 : 2)
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        ImpactEvidence.shared.configure()
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var driver: ImpactDriver?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let journey = UIKitJourney()
        window.rootViewController = journey.root
        self.window = window
        window.makeKeyAndVisible()
        let driver = ImpactDriver(journey: journey, window: window)
        self.driver = driver
        Task { await driver.run() }
    }
    func sceneWillResignActive(_ scene: UIScene) { ImpactEvidence.shared.record("inactive") }
    func sceneDidDisconnect(_ scene: UIScene) { ImpactEvidence.shared.record("disconnected") }
}
