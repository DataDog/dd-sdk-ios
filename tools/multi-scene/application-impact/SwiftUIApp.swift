/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import UIKit
@_spi(Experimental) import DatadogRUM

private enum Screen: Hashable { case home, detail(Int), sheet(Int) }
private struct Presented: Identifiable, Equatable { let id: Int }
private struct RouteState: Equatable { var path: [Int] = []; var sheet: Presented? }

@MainActor
private final class JourneyModel: ObservableObject {
    @Published var accepted = RouteState()
    @Published var scroll = 0
    var appeared: [String: Int] = [:]
    func appear(_ screen: String) {
        appeared[screen, default: 0] += 1
        ImpactEvidence.shared.record("native-appear", ["screen": screen])
    }
}

@MainActor
private struct Page: View {
    let name: String
    @ObservedObject var model: JourneyModel
    var body: some View {
        ScrollViewReader { proxy in
            List(0..<150, id: \.self) { row in
                Label {
                    VStack(alignment: .leading) {
                        Text("Item \(row)")
                        Text("Local deterministic application data").font(.caption)
                    }
                } icon: { Image(systemName: "chart.bar.fill") }.id(row)
            }
            .onChange(of: model.scroll) { value in
                withAnimation(.linear(duration: 0.5)) { proxy.scrollTo(value % 2 == 0 ? 0 : 100, anchor: .top) }
            }
        }
        .navigationTitle(name)
        .onAppear { model.appear(name) }
    }
}

@MainActor
private struct Content: View {
    @ObservedObject var model: JourneyModel
    @ViewBuilder private func page(_ name: String) -> some View {
#if CANDIDATE
        Page(name: name, model: model)
#else
        Page(name: name, model: model).trackRUMView(name: name)
#endif
    }
    private var stack: some View {
        NavigationStack(path: $model.accepted.path) {
            page("home").navigationDestination(for: Int.self) { _ in page("detail") }
        }
        .sheet(item: $model.accepted.sheet) { _ in page("sheet") }
    }
    var body: some View {
#if CANDIDATE
        RUMNavigationHost(observing: model.$accepted, destination: { state in
            if let item = state.sheet { return .presentation(Screen.sheet(item.id)) }
            if let last = state.path.last { return .route(Screen.detail(last), occurrence: last) }
            return .root(Screen.home)
        }) { stack }
#else
        stack
#endif
    }
}

@MainActor
final class SwiftUIJourney: ImpactJourney {
    private let model = JourneyModel()
    lazy var root: UIViewController = UIHostingController(rootView: Content(model: model))
    private var expectedAppearances: [String: Int] = [:]
    func perform(step: Int, cycle: Int) {
        if step == 2 || step == 4 {
            let screen = step == 2 ? "detail" : "sheet"
            expectedAppearances[screen] = model.appeared[screen, default: 0] + 1
        }
        withAnimation {
            switch step {
            case 0, 3, 5: model.scroll += 1
            case 2: model.accepted = RouteState(path: [cycle + 1])
            case 4: model.accepted = RouteState(path: [cycle + 1], sheet: Presented(id: cycle + 1))
            case 6: model.accepted = RouteState(path: [cycle + 1])
            case 7: model.accepted = RouteState()
            default: break
            }
        }
    }
    func verify(step: Int, cycle: Int) -> Bool {
        let sheet = step == 4 || step == 5
        let home = step < 2 || step == 7
        let modal = root.presentedViewController
        guard model.accepted.path == (home ? [] : [cycle + 1]),
              (model.accepted.sheet != nil) == sheet, (modal != nil) == sheet,
              root.view.window != nil, root.transitionCoordinator == nil,
              model.appeared["home", default: 0] > 0 else { return false }
        if step >= 2 && step < 7, model.appeared["detail", default: 0] != expectedAppearances["detail"] { return false }
        if sheet, model.appeared["sheet", default: 0] != expectedAppearances["sheet"] { return false }
        return true
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
        let journey = SwiftUIJourney()
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
