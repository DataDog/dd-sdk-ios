/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SwiftUI
import ObjectiveC
import DatadogCore
@_spi(Internal) import DatadogInternal
@testable import DatadogRUM

private final class WeakBox {
    weak var value: AnyObject?
    init(_ value: AnyObject?) { self.value = value }
}

@MainActor
private enum Fixture {
    static var started = false
    static var checks: [String: Bool] = [:]
    static var cycles: [[String: Any]] = []
    static var sources: [RUMSwiftUINavigationOccurrenceSource] = []
    static var registrations: [WeakBox] = []
    static var states: [WeakBox] = []
    static var readers: [WeakBox] = []
    static var controllers: [WeakBox] = []

    static func drain(_ monitor: Monitor?) async {
        if let monitor {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                monitor.currentSessionID { _ in continuation.resume() }
            }
        }
        for _ in 0..<10 { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    static func reflected<T>(_ object: Any, _ label: String, as type: T.Type) -> T? {
        guard let value = Mirror(reflecting: object).children.first(where: { $0.label == label })?.value else { return nil }
        if let typed = value as? T { return typed }
        return Mirror(reflecting: value).children.first?.value as? T
    }

    static func captureRegistration(_ source: RUMSwiftUINavigationOccurrenceSource) -> Bool {
        guard let entries = Mirror(reflecting: source).children.first(where: { $0.label == "registrations" })?.value else { return false }
        var found = false
        for child in Mirror(reflecting: entries).children {
            if let registration: RUMSwiftUINavigationOccurrenceRegistration = reflected(child.value, "registration", as: RUMSwiftUINavigationOccurrenceRegistration.self) {
                registrations.append(WeakBox(registration))
                states.append(WeakBox(reflected(registration, "state", as: RUMViewTrackingState.self)))
                found = true
            }
        }
        return found
    }

    static func captureReaders(_ view: UIView) {
        if view is RUMSceneIdentifierReader.ObserverView { readers.append(WeakBox(view)) }
        view.subviews.forEach(captureReaders)
    }

    static func implementations() -> [UInt] {
        let methods: [(AnyClass, Selector)] = [
            (UIViewController.self, #selector(UIViewController.viewDidAppear(_:))),
            (UIViewController.self, #selector(UIViewController.viewDidDisappear(_:))),
            (UIApplication.self, #selector(UIApplication.sendEvent(_:)))
        ]
        return methods.compactMap { cls, selector in
            class_getInstanceMethod(cls, selector).map { unsafeBitCast(method_getImplementation($0), to: UInt.self) }
        }
    }

    static func configure() -> [String: WeakBox] {
        Datadog.initialize(with: .init(clientToken: "local-fixture-no-credentials", env: "swiftui-lifetime"), trackingConsent: .granted)
        var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000168")
        configuration.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        configuration.uiKitActionsPredicate = nil
        configuration.vitalsUpdateFrequency = nil
        configuration.trackSlowFrames = false
        configuration.trackFrustrations = false
        configuration.telemetrySampleRate = 0
        configuration.customEndpoint = URL(string: "http://127.0.0.1:9/rum")!
        RUM.enable(with: configuration)
        let instrumentation = CoreRegistry.default.get(feature: RUMFeature.self)?.instrumentation
        return ["instrumentation": WeakBox(instrumentation), "handler": WeakBox(instrumentation?.viewsHandler),
                "arbiter": WeakBox(instrumentation?.swiftUIInteractiveTransitionArbiter), "core": WeakBox(CoreRegistry.default)]
    }

    static func mount(index: Int, source: RUMSwiftUINavigationOccurrenceSource, window: UIWindow) -> UIViewController {
        let key = RUMViewOccurrenceKey(index)
        source.acceptDestination(occurrenceKey: key, bindingGeneration: 1, change: .initial(requiresBootstrap: false))
        let configuration = RUMViewTrackingState.Configuration(occurrenceKey: key, bindingGeneration: 1, descriptor: .init(name: "Keyed \(index)", path: "keyed", attributes: [:]))
        source.reconcileCurrentDestination(configuration: configuration, viewsHandler: CoreRegistry.default.get(feature: RUMFeature.self)?.instrumentation.viewsHandler)
        let host = UIHostingController(rootView: Text("Keyed \(index)").trackRUMView(name: "Keyed \(index)", occurrenceKey: key, bindingGeneration: 1, navigationOccurrenceSource: source))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return host
    }

    static func run(window: UIWindow) async {
        guard !started else { return }
        started = true
        let original = implementations()
        let objects = configure()
        var monitor = RUMMonitor.shared() as? Monitor
        await drain(monitor)
        checks["native_scene_mounted"] = window.windowScene != nil && UIApplication.shared.applicationState == .active
        let arbiterMatchesAvailability: Bool
        if #available(iOS 27.0, *) {
            arbiterMatchesAvailability = objects["arbiter"]?.value != nil
        } else {
            arbiterMatchesAvailability = objects["arbiter"]?.value == nil
        }
        checks["instrumentation_exists"] = ["instrumentation", "handler", "core"].allSatisfy { objects[$0]?.value != nil }
            && arbiterMatchesAvailability
        let enabled = implementations()
        checks["three_selectors_instrumented"] = original.count == 3 && zip(original, enabled).allSatisfy { $0 != $1 }
        guard let scene = window.windowScene else { finish(); return }
        let sceneID = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        for index in 0..<25 {
            let source = RUMSwiftUINavigationOccurrenceSource()
            sources.append(source)
            var host: UIViewController? = mount(index: index, source: source, window: window)
            controllers.append(WeakBox(host))
            await drain(monitor)
            let mounted = host?.viewIfLoaded?.window === window
            let before = registrations.count
            let registered = captureRegistration(source)
            if let view = host?.viewIfLoaded { captureReaders(view) }
            let tracked = monitor?.rumContextSnapshot(for: .scene(sceneID))?.viewName == "Keyed \(index)"
            checks["cycle_\(index)_mounted_and_registered"] = mounted && registered && tracked && registrations.count > before
            window.rootViewController = UIViewController()
            host = nil
            await drain(monitor)
            cycles.append(["index": index, "phase": index < 5 ? "warmup" : "measured",
                           "registrations": registrations.filter { $0.value != nil }.count,
                           "states": states.filter { $0.value != nil }.count,
                           "readers": readers.filter { $0.value != nil }.count,
                           "controllers": controllers.filter { $0.value != nil }.count])
        }
        checks["registrations_released"] = registrations.allSatisfy { $0.value == nil }
        checks["tracking_states_released"] = states.allSatisfy { $0.value == nil }
        checks["readers_released"] = readers.allSatisfy { $0.value == nil }
        checks["controllers_released"] = controllers.allSatisfy { $0.value == nil }
        monitor = nil
        Datadog.stopInstance()
        await drain(nil)
        for (name, object) in objects { checks[name + "_released"] = object.value == nil }
        checks["three_selectors_restored"] = implementations() == original
        finish(details: ["cycles": cycles, "source_count_retained": sources.count, "scene_id": sceneID.rawValue])
    }

    static func finish(details: [String: Any] = [:]) {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--run-id")
        let runID = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? ""
        let result: [String: Any] = ["run_id": runID, "checks": checks, "details": details]
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.json")
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let window else { return }
        Task { await Fixture.run(window: window) }
    }
}
