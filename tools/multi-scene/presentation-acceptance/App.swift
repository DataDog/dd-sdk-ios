/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SwiftUI
import DatadogCore
@_spi(Internal) import DatadogInternal
@testable import DatadogLogs
@_spi(Experimental) @testable import DatadogRUM

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [[String: String]] = []
    func append(_ row: [String: String]) { lock.lock(); rows.append(row); lock.unlock() }
    func snapshot() -> [[String: String]] { lock.lock(); defer { lock.unlock() }; return rows }
}

private struct AutomaticPredicate: SwiftUIRUMViewsPredicate {
    func rumView(for extractedViewName: String) -> RUMView? { nil }
}

@available(iOS 27.0, *)
private struct Item: Identifiable {
    let id: String
    let name: String
    let style: RUMNavigationPresentationStyle
}

@available(iOS 27.0, *)
@MainActor
private final class Model: ObservableObject {
    @Published var presented: Item?
    var policy = "accept"
    var canonical: Item?
    var writes = 0
    var transactionForwarded = false
    var nativeDismiss: (() -> Void)?
    var appeared: [String] = []
    var disappeared: [String] = []
    let mode: String
    init(mode: String) { self.mode = mode }
    var binding: Binding<Item?> {
        Binding(get: { self.presented }, set: { item, transaction in
            self.writes += 1
            self.transactionForwarded = transaction.disablesAnimations
            if self.policy == "accept" { self.presented = item }
            if self.policy == "canonical" { self.presented = self.canonical }
            if !Fixture.writeLabel.isEmpty { Fixture.emitCurrent("inside-" + Fixture.writeLabel) }
        })
    }
}

@available(iOS 27.0, *)
@MainActor
private struct PresentedContent: SwiftUI.View {
    let item: Item
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss
    var body: some SwiftUI.View {
        Text(item.name)
            .onAppear {
                model.appeared.append(item.name)
                model.nativeDismiss = { dismiss() }
            }
            .onDisappear { model.disappeared.append(item.name) }
    }
}

@available(iOS 27.0, *)
@MainActor
private struct Content: SwiftUI.View {
    @ObservedObject var model: Model
    var body: some SwiftUI.View {
        Fixture.bodyPasses += 1
        return RUMNavigationStack(
            path: .constant([String]()), presented: model.binding,
            root: RUMView(name: model.mode + "-Home"),
            destination: { RUMView(name: $0) },
            presentation: { RUMNavigationPresentation(view: RUMView(name: $0.name), style: $0.style) },
            rootContent: { Text(model.mode + "-Home") },
            destinationContent: { Text($0) },
            presentedContent: { PresentedContent(item: $0, model: model) },
            onPresentationDismiss: { item in
                Fixture.dismissed.append(item.name)
                Fixture.emitCurrent("callback-" + item.name)
            }
        )
    }
}

@MainActor
private enum Fixture {
    static var started = false
    static var checks: [String: Bool] = [:]
    static var scenarios: [[String: Any]] = []
    static var bodyPasses = 0
    static var writeLabel = ""
    static var dismissed: [String] = []
    static var monitor: Monitor?
    static var logger: LoggerProtocol?
    @available(iOS 27.0, *) static var bindings: [String: Binding<Item?>] = [:]
    @available(iOS 27.0, *) static var callbacks: [String: RUMPresentationFixtureCallbacks] = [:]

    static func drain(_ monitor: Monitor) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            monitor.currentSessionID { _ in continuation.resume() }
        }
    }

    static func settle() async {
        for _ in 0..<10 { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    static func readers(in view: UIView) -> [RUMSceneIdentifierReader.ObserverView] {
        (view as? RUMSceneIdentifierReader.ObserverView).map { [$0] } ?? view.subviews.flatMap { readers(in: $0) }
    }

    static func configure(events: Events) -> (Monitor, LoggerProtocol)? {
        Datadog.initialize(with: .init(clientToken: "local-fixture-no-credentials", env: "presentation-acceptance"), trackingConsent: .granted)
        var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000173")
        configuration.uiKitViewsPredicate = nil
        configuration.swiftUIViewsPredicate = AutomaticPredicate()
        configuration.uiKitActionsPredicate = nil
        configuration.vitalsUpdateFrequency = nil
        configuration.trackSlowFrames = false
        configuration.trackFrustrations = false
        configuration.telemetrySampleRate = 0
        configuration.featureFlags = [.viewUpdates: false]
        configuration.customEndpoint = URL(string: "http://127.0.0.1:9/rum")!
        configuration.viewEventMapper = { event in
            events.append(["type": "view", "id": event.view.id, "name": event.view.name ?? "", "session": event.session.id])
            return event
        }
        configuration.resourceEventMapper = { event in
            events.append(["type": "resource", "view": event.view.id, "url": event.resource.url, "session": event.session.id])
            return event
        }
        RUM.enable(with: configuration)
        Logs.enable(with: .init(eventMapper: { event in
            events.append(["type": "log", "message": event.message,
                           "view": event.attributes.internalAttributes?["view.id"] as? String ?? "",
                           "session": event.attributes.internalAttributes?["session_id"] as? String ?? ""])
            return event
        }, customEndpoint: URL(string: "http://127.0.0.1:9/logs")!))
        guard let monitor = RUMMonitor.shared() as? Monitor else { return nil }
        return (monitor, Logger.create(with: .init(bundleWithTraceEnabled: false)))
    }

    static func emit(_ name: String, monitor: Monitor, logger: LoggerProtocol) {
        // These reader lifecycle callbacks have no UI-event handoff. Use the
        // ordinary APIs immediately; their accepted command ordering must hold.
        monitor.startResource(resourceKey: name, url: URL(string: "https://fixture.invalid/\(name)")!, attributes: [:])
        logger.info(name)
        monitor.stopResource(resourceKey: name, statusCode: 200, kind: .native, size: 1, attributes: [:])
    }

    static func checkMarkers(_ name: String, context: RUMCoreContext?, events: Events) {
        let rows = events.snapshot()
        let resources = rows.filter { $0["type"] == "resource" && $0["url"] == "https://fixture.invalid/\(name)" }
        let logs = rows.filter { $0["type"] == "log" && $0["message"] == name }
        checks[name + "_resource_owner"] = context != nil && resources.count == 1
            && resources[0]["view"] == context?.viewID && resources[0]["session"] == context?.sessionID
        checks[name + "_log_owner"] = context != nil && logs.count == 1
            && logs[0]["view"] == context?.viewID && logs[0]["session"] == context?.sessionID
    }

    static func emitCurrent(_ name: String) {
        guard let monitor, let logger else { return }
        emit(name, monitor: monitor, logger: logger)
    }

    @available(iOS 27.0, *)
    static func waitForOwner(_ name: String, scene: RUMSceneIdentifier, monitor: Monitor, model: Model? = nil) async -> RUMCoreContext? {
        for _ in 0..<240 {
            await drain(monitor)
            let context = monitor.rumContextSnapshot(for: .scene(scene))
            if context?.viewName == name && (model == nil || model!.appeared.contains(name)) { return context }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return nil
    }

    @available(iOS 27.0, *)
    static func scenario(_ mode: String, window: UIWindow) async {
        let events = Events()
        guard let (monitor, logger) = configure(events: events), let scene = window.windowScene,
              let instrumentation = CoreRegistry.default.get(feature: RUMFeature.self)?.instrumentation else { return }
        self.monitor = monitor; self.logger = logger
        bindings = [:]; callbacks = [:]; dismissed = []; writeLabel = ""
        let model = Model(mode: mode)
        RUMPresentationFixtureHooks.onBinding = { style, value in
            if let binding = value as? Binding<Item?> {
                bindings[style == .sheet ? "sheet" : "cover"] = binding
            }
        }
        RUMPresentationFixtureHooks.onBoundary = { content, value in
            if let content = content as? PresentedContent, callbacks[content.item.name] == nil {
                callbacks[content.item.name] = value
            }
        }
        let host = UIHostingController(rootView: Content(model: model))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        let sceneID = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        let homeName = mode + "-Home"
        let initialHome = await waitForOwner(homeName, scene: sceneID, monitor: monitor)
        checks[mode + "_home_mounted"] = initialHome?.viewID != nil && host.viewIfLoaded?.window === window
        let peerID = RUMSceneIdentifier(rawValue: "logical-peer")
        instrumentation.viewsHandler.notify_semanticDestinationAppear(identity: "peer", name: "Peer", path: "/peer", attributes: [:], sceneIdentifier: peerID)
        await drain(monitor)
        let peer = monitor.rumContextSnapshot(for: .scene(peerID))
        checks[mode + "_peer_ready"] = peer?.viewID != nil
        let sheet = Item(id: "same", name: mode + "-Sheet", style: .sheet)
        model.presented = sheet
        let first = await waitForOwner(sheet.name, scene: sceneID, monitor: monitor, model: model)
        await settle()
        checks[mode + "_sheet_mounted"] = first?.viewID != nil && host.presentedViewController?.viewIfLoaded?.window != nil
        checks[mode + "_bindings_captured"] = bindings.count == 2
        checks[mode + "_boundary_captured"] = callbacks[sheet.name] != nil
        guard let sheetBinding = bindings["sheet"], let oldCallbacks = callbacks[sheet.name], first != nil else { return }
        var expectedFinal = first
        var expectedDismissName = sheet.name
        var expectedOwnedNames = [sheet.name]
        let beforeBody = bodyPasses
        let beforeWrites = model.writes
        var transaction = Transaction()
        transaction.disablesAnimations = true
        if mode == "reject" {
            model.policy = "reject"
            writeLabel = mode
            sheetBinding.transaction(transaction).wrappedValue = nil
            emitCurrent("return-" + mode)
            checks[mode + "_before_render"] = bodyPasses == beforeBody
            checks[mode + "_one_write"] = model.writes == beforeWrites + 1
            checks[mode + "_transaction"] = model.transactionForwarded
            checks[mode + "_accepted_item"] = model.presented?.name == sheet.name && sheetBinding.wrappedValue?.name == sheet.name
            writeLabel = ""
            await drain(monitor)
            await settle()
            checkMarkers("inside-" + mode, context: first, events: events)
            checkMarkers("return-" + mode, context: first, events: events)
            checks[mode + "_no_false_dismissal"] = dismissed.isEmpty
            checks[mode + "_same_owner"] = monitor.rumContextSnapshot(for: .scene(sceneID))?.viewID == first?.viewID
            model.policy = "accept"
        } else {
            let cover = Item(id: "same", name: mode + "-Cover", style: .fullScreenCover)
            expectedDismissName = cover.name
            expectedOwnedNames.append(cover.name)
            if mode == "canonical" {
                model.policy = "canonical"; model.canonical = cover
                writeLabel = mode
                sheetBinding.transaction(transaction).wrappedValue = Item(id: "proposal", name: "NeverAccepted", style: .sheet)
                emitCurrent("return-" + mode)
                checks[mode + "_before_render"] = bodyPasses == beforeBody
                checks[mode + "_one_write"] = model.writes == beforeWrites + 1
                checks[mode + "_transaction"] = model.transactionForwarded
                checks[mode + "_accepted_item"] = model.presented?.name == cover.name
                writeLabel = ""
            } else {
                sheetBinding.transaction(transaction).wrappedValue = cover
            }
            expectedFinal = await waitForOwner(cover.name, scene: sceneID, monitor: monitor, model: model)
            await settle()
            checks[mode + "_cover_mounted"] = expectedFinal?.viewID != nil && host.presentedViewController?.viewIfLoaded?.window != nil
            checks[mode + "_fresh_cover"] = expectedFinal?.viewID != first?.viewID
            if mode == "canonical" {
                checkMarkers("inside-" + mode, context: first, events: events)
                checkMarkers("return-" + mode, context: first, events: events)
            }
            oldCallbacks.disappear()
            oldCallbacks.mount(sceneID)
            emitCurrent("stale-" + mode)
            await drain(monitor)
            await settle()
            checks[mode + "_old_callback_preserves_cover"] = monitor.rumContextSnapshot(for: .scene(sceneID))?.viewID == expectedFinal?.viewID
            checkMarkers("stale-" + mode, context: expectedFinal, events: events)
            model.policy = "accept"
            if mode == "occurrence" {
                // Return to the same customer ID through another materialized sheet.
                guard let coverBinding = bindings["cover"] else { return }
                let final = Item(id: "same", name: mode + "-SheetAgain", style: .sheet)
                coverBinding.wrappedValue = final
                let last = await waitForOwner(final.name, scene: sceneID, monitor: monitor, model: model)
                checks[mode + "_second_sheet_mounted"] = last?.viewID != nil
                checks[mode + "_fresh_second_sheet"] = last?.viewID != first?.viewID && last?.viewID != expectedFinal?.viewID
                expectedFinal = last; expectedDismissName = final.name; expectedOwnedNames.append(final.name)
                await settle()
                await drain(monitor)
                checks[mode + "_stable_before_old_callback"] = monitor.rumContextSnapshot(for: .scene(sceneID))?.viewID == last?.viewID
                oldCallbacks.disappear(); oldCallbacks.mount(sceneID)
                emitCurrent("earlier-" + mode)
                await drain(monitor); await settle()
                checks[mode + "_old_callback_preserves_later_sheet"] = monitor.rumContextSnapshot(for: .scene(sceneID))?.viewID == last?.viewID
                checkMarkers("earlier-" + mode, context: last, events: events)
            }
        }
        checks[mode + "_native_dismiss_ready"] = model.nativeDismiss != nil
        writeLabel = "native-dismiss-" + mode
        model.nativeDismiss?()
        let revealed = await waitForOwner(homeName, scene: sceneID, monitor: monitor)
        for _ in 0..<120 where !dismissed.contains(expectedDismissName) {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        writeLabel = ""
        await drain(monitor); await settle()
        checks[mode + "_fresh_home"] = revealed?.viewID != nil && revealed?.viewID != initialHome?.viewID
        checks[mode + "_native_dismiss_callback"] = dismissed == [expectedDismissName]
        checkMarkers("callback-" + expectedDismissName, context: revealed, events: events)
        checks[mode + "_peer_unchanged"] = monitor.rumContextSnapshot(for: .scene(peerID))?.viewID == peer?.viewID
        let rows = events.snapshot()
        let views = rows.filter { $0["type"] == "view" }
        checks[mode + "_exact_presentations"] = expectedOwnedNames.allSatisfy { name in
            Set(views.filter { $0["name"] == name }.compactMap { $0["id"] }).count == 1
        } && !views.contains { $0["name"] == "NeverAccepted" }
        checks[mode + "_exact_home_occurrences"] = Set(views.filter { $0["name"] == homeName }.compactMap { $0["id"] }).count == 2
        checks[mode + "_one_peer_occurrence"] = Set(views.filter { $0["name"] == "Peer" }.compactMap { $0["id"] }).count == 1
        scenarios.append(["mode": mode, "scene_id": sceneID.rawValue, "peer": "logical",
                          "writes": model.writes, "appeared": model.appeared, "disappeared": model.disappeared,
                          "dismissed": dismissed, "events": rows, "body_passes": bodyPasses])
        RUMPresentationFixtureHooks.onBinding = nil; RUMPresentationFixtureHooks.onBoundary = nil
        bindings = [:]; callbacks = [:]
        window.rootViewController = UIViewController()
        await settle(); await drain(monitor)
        Datadog.stopInstance()
        self.monitor = nil; self.logger = nil
    }

    static func run(window: UIWindow) async {
        guard !started else { return }; started = true
        await settle()
        checks["native_scene_active"] = window.windowScene != nil && UIApplication.shared.applicationState == .active
        if #available(iOS 27.0, *) {
            for mode in ["reject", "canonical", "occurrence"] { await scenario(mode, window: window) }
        }
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--run-id")
        let runID = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? ""
        let result: [String: Any] = ["run_id": runID, "checks": checks, "details": ["scenarios": scenarios]]
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.json")
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
    }
}

@main final class AppDelegate: UIResponder, UIApplicationDelegate {}
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene); window.rootViewController = UIViewController()
        self.window = window; window.makeKeyAndVisible()
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let window else { return }
        Task { await Fixture.run(window: window) }
    }
}
