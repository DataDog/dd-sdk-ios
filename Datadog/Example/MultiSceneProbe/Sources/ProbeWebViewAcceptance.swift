/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import WebKit
import DatadogCore
import DatadogSessionReplay
import DatadogWebViewTracking
#if DEBUG
@_spi(Experimental)
@testable import DatadogRUM
@_spi(Internal)
import DatadogInternal
#endif

internal enum ProbeWebViewAcceptance {
    #if DEBUG
    @MainActor private static var running = false

    static func configure() {
        SessionReplay.enable(with: .init(replaySampleRate: 100))
    }

    @MainActor
    static func start() -> ProbeStepExecutionResult {
        guard !running else {
            return .rejected(reason: "WebView batch already started")
        }
        running = true
        Task { @MainActor in
            do {
                try await run()
                record(ProbeWebViewContract.completed)
            } catch {
                record(ProbeWebViewContract.completed, result: .fail, reason: String(describing: error))
            }
        }
        return .accepted
    }

    private enum FixtureError: Error { case missing(String) }

    private static func require(_ condition: Bool, _ label: String) throws {
        if !condition { throw FixtureError.missing(label) }
    }

    private static func record(
        _ name: String,
        owner: RUMCoreContext? = nil,
        source: ProbeSourceContext? = nil,
        result: ProbeSemanticResultState = .pass,
        reason: String? = nil
    ) {
        ProbeRuntime.eventRecorder.record(ProbeSignal(
            kind: .assertion,
            evidenceSource: owner == nil ? .probe : .internalHook,
            sourceContext: source,
            rumContext: owner.map {
                ProbeRUMContext(sessionID: $0.sessionID, viewID: $0.viewID, viewName: $0.viewName)
            },
            name: name,
            result: result,
            reason: reason
        ))
    }

    @MainActor
    fileprivate static func callback(_ message: WKScriptMessage) -> ProbeWebViewMessage? {
        guard let webView = message.webView, let body = message.body as? String,
              let observed = ProbeWebViewMessage.decode(
                body,
                webViewIdentity: String(describing: ObjectIdentifier(webView)),
                nativeSceneID: webView.window?.windowScene?.session.persistentIdentifier
              ), observed.runID == ProbeRuntime.runID else {
            record("web-malformed-callback", result: .fail)
            return nil
        }
        return observed
    }

    fileprivate static func recordCallback(_ observed: ProbeWebViewMessage) {
        ProbeRuntime.eventRecorder.record(ProbeSignal(
            kind: .webBridgeMessage,
            evidenceSource: .webKitCallback,
            sourceContext: .init(
                logicalSceneID: observed.sourceScene,
                nativeSceneID: observed.nativeSceneID,
                screen: "web",
                phase: observed.phase
            ),
            eventID: observed.browserViewID,
            name: observed.phase,
            webMessage: observed,
            result: .pass
        ))
    }

    @MainActor
    private static func window(_ label: String) throws -> UIWindow {
        guard let handle = ProbeRuntime.sceneRegistry.handle(logicalSceneID: label),
              let window = ProbeRuntime.sceneRegistry.window(for: handle),
              window.windowScene != nil, window.rootViewController != nil else {
            throw FixtureError.missing("native window " + label)
        }
        return window
    }

    @MainActor
    private static func waitFor(_ predicate: () -> Bool, _ label: String) async throws {
        for _ in 0..<500 {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw FixtureError.missing(label)
    }

    private static func replayEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            CoreRegistry.default.scope(for: RUMFeature.self).context { context in
                continuation.resume(returning: context.hasReplay == true)
            }
        }
    }

    private static var nowMilliseconds: Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private static func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw FixtureError.missing("JSON encoding")
        }
        return text
    }

    @MainActor
    private static func makeWebView(in window: UIWindow) throws -> WKWebView {
        guard let host = window.rootViewController?.view else {
            throw FixtureError.missing("native host view")
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = ProbeWebContentController()
        let webView = WKWebView(frame: host.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isUserInteractionEnabled = false
        WebViewTracking.enable(webView: webView, hosts: [ProbeWebViewContract.host])
        host.addSubview(webView)
        try require(webView.window === window, "mounted WebView")
        return webView
    }

    @MainActor
    private static func load(_ webView: WKWebView, document: String) async throws {
        let encodedDocument = try json([document]) + "[0]"
        let html = "<html><body>Multi-scene bridge fixture<script>window.__probeDocumentID = "
            + encodedDocument + ";</script></body></html>"
        guard let url = URL(string: "https://" + ProbeWebViewContract.host + "/" + document) else {
            throw FixtureError.missing("document URL")
        }
        webView.loadHTMLString(html, baseURL: url)
        let readiness = "document.readyState === 'complete' && window.__probeDocumentID === "
            + encodedDocument + " && typeof window.DatadogEventBridge.send === 'function'"
        for _ in 0..<500 {
            if let ready = try? await webView.evaluateJavaScript(readiness) as? Bool, ready {
                record("web-document-ready-" + document)
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw FixtureError.missing("fresh document readiness")
    }

    @MainActor
    private static func nativeOwner(
        _ name: String, scene: String, window: UIWindow, monitor: Monitor
    ) async throws -> RUMCoreContext {
        guard let sceneID = window.windowScene?.session.persistentIdentifier else {
            throw FixtureError.missing("native scene for view")
        }
        record("web-native-start-" + name)
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: sceneID) {
            monitor.startView(key: name, name: name, attributes: [
                ProbeRuntime.Attribute.runID: ProbeRuntime.runID,
                ProbeRuntime.Attribute.viewScene: scene,
                ProbeRuntime.Attribute.viewSceneSessionID: sceneID,
                ProbeRuntime.Attribute.viewScreen: name,
            ])
        }
        try await waitFor({
            guard let context = monitor.rumContextSnapshot(for: .scene(.init(rawValue: sceneID))),
                  context.viewName == name else { return false }
            return ProbeRuntime.eventRecorder.snapshot().contains {
                $0.kind == .rumViewSnapshot && $0.rumContext?.viewID == context.viewID
                    && $0.rumContext?.sessionHasReplay == true && $0.rumContext?.viewActive == true
            }
        }, "independent Replay-enabled native view " + name)
        guard let owner = monitor.rumContextSnapshot(for: .scene(.init(rawValue: sceneID))) else {
            throw FixtureError.missing("captured native owner")
        }
        record("web-owner-" + name, owner: owner)
        return owner
    }

    @MainActor
    private static func emit(
        _ phase: String,
        webView: WKWebView,
        window: UIWindow?,
        owner: RUMCoreContext?,
        document: String,
        spoof: String
    ) async throws {
        try require(webView.window === window, "attachment before " + phase)
        let source = ProbeSourceContext(
            logicalSceneID: ProbeWebViewContract.source(for: phase),
            nativeSceneID: webView.window?.windowScene?.session.persistentIdentifier,
            screen: "web",
            phase: phase
        )
        record("web-dispatch-boundary-" + phase, owner: owner, source: source)
        let boundary = nowMilliseconds
        try await waitFor({ nowMilliseconds > boundary }, "strict browser timestamp")
        let identifier = UUID().uuidString.lowercased()
        let event: [String: Any] = [
            "application": ["id": "browser-app"],
            "session": ["id": "browser-session", "type": "user", "has_replay": true],
            "type": "view", "source": "browser", "date": nowMilliseconds,
            "service": ProbeRuntime.serviceName,
            "view": [
                "id": identifier, "name": phase,
                "url": "https://" + ProbeWebViewContract.host + "/" + document,
                "is_active": false, "time_spent": 1_000_000,
                "action": ["count": 0], "resource": ["count": 0],
                "error": ["count": 0], "long_task": ["count": 0],
                "loading_type": "initial_load",
            ],
            "_dd": ["format_version": 2, "document_version": 1],
            "context": [
                "probe": [
                    "run_id": ProbeRuntime.runID, "phase": phase,
                    "source_scene": ProbeWebViewContract.source(for: phase), "document_id": document,
                ],
            ],
            "_dd.internal.native_scene_id": spoof,
        ]
        let body = try json(["eventType": "view", "event": event])
        let script = "window.DatadogEventBridge.send(" + (try json([body])) + "[0]); true"
        _ = try await webView.evaluateJavaScript(script)
        try await waitFor({
            ProbeRuntime.eventRecorder.snapshot().contains {
                $0.kind == .webBridgeMessage && $0.eventID == identifier && $0.name == phase
            }
        }, "actual WebKit callback " + phase)
        try require(webView.window === window, "attachment changed during callback")
    }

    @MainActor
    private static func cleanup(_ webView: WKWebView) {
        webView.stopLoading()
        WebViewTracking.disable(webView: webView)
        webView.removeFromSuperview()
    }

    @MainActor
    private static func run() async throws {
        guard #available(iOS 27.0, *), let monitor = RUMMonitor.shared() as? Monitor else {
            throw FixtureError.missing("live monitor")
        }
        let windowA = try window("scene-A")
        let windowB = try window("scene-B")
        guard let sceneA = windowA.windowScene, let sceneB = windowB.windowScene else {
            throw FixtureError.missing("native scenes")
        }
        try require(sceneA !== sceneB, "distinct actual scenes")
        for _ in 0..<250 {
            if await replayEnabled() { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try require(await replayEnabled(), "actual Replay context")
        record("web-replay-ready")
        let webA = try makeWebView(in: windowA)
        defer { cleanup(webA) }
        let webB = try makeWebView(in: windowB)
        defer { cleanup(webB) }
        try require(webA !== webB, "distinct WebViews")
        record("web-two-mounted-containers")
        let documentA = ProbeRuntime.runID + "/A/initial"
        let documentB = ProbeRuntime.runID + "/B/initial"
        try await load(webA, document: documentA)
        try await load(webB, document: documentB)
        let ownerA = try await nativeOwner("WebNativeA1", scene: "scene-A", window: windowA, monitor: monitor)
        let ownerB = try await nativeOwner("WebNativeB1", scene: "scene-B", window: windowB, monitor: monitor)
        try require(ownerA.viewID != ownerB.viewID && ownerA.sessionID == ownerB.sessionID, "native owner identities")
        guard let representative = monitor.rumContextSnapshot(for: .processRepresentative) else {
            throw FixtureError.missing("process representative")
        }
        try require(representative.viewID == ownerB.viewID, "B represents before A emission")
        record("web-representative-before-a", owner: representative)
        try await emit(
            "web-a-original",
            webView: webA,
            window: windowA,
            owner: ownerA,
            document: documentA,
            spoof: sceneB.session.persistentIdentifier
        )
        try await emit(
            "web-b-original",
            webView: webB,
            window: windowB,
            owner: ownerB,
            document: documentB,
            spoof: sceneA.session.persistentIdentifier
        )
        let afterOriginal = nowMilliseconds
        try await waitFor({ nowMilliseconds > afterOriginal }, "navigation after original browser dates")
        record("web-navigation-boundary")
        let ownerA2 = try await nativeOwner("WebNativeA2", scene: "scene-A", window: windowA, monitor: monitor)
        try require(ownerA2.viewID != ownerA.viewID && ownerA2.viewID != ownerB.viewID, "fresh A navigation owner")
        let documentA2 = ProbeRuntime.runID + "/A/navigation"
        try await load(webA, document: documentA2)
        try await emit(
            "web-a-navigation",
            webView: webA,
            window: windowA,
            owner: ownerA2,
            document: documentA2,
            spoof: sceneB.session.persistentIdentifier
        )
        record("web-detach-boundary")
        webA.removeFromSuperview()
        try require(webA.window == nil, "A detached")
        record("web-detached")
        try await emit(
            "web-a-detached",
            webView: webA,
            window: nil,
            owner: nil,
            document: documentA2,
            spoof: sceneB.session.persistentIdentifier
        )
        record("web-rebind-boundary")
        guard let hostB = windowB.rootViewController?.view else {
            throw FixtureError.missing("B host")
        }
        webA.frame = hostB.bounds
        hostB.addSubview(webA)
        try require(webA.window === windowB, "same A rebound into B")
        record("web-rebound")
        try await emit(
            "web-a-rebound-b",
            webView: webA,
            window: windowB,
            owner: ownerB,
            document: documentA2,
            spoof: sceneA.session.persistentIdentifier
        )
        record("web-teardown-boundary")
        cleanup(webA)
        try require(webA.window == nil && !webA.configuration.userContentController.userScripts.contains {
            $0.source.hasPrefix("/* DatadogEventBridge */")
        }, "A tracking disabled and removed")
        record("web-a-torn-down")
        try await emit(
            "web-b-after-teardown",
            webView: webB,
            window: windowB,
            owner: ownerB,
            document: documentB,
            spoof: sceneA.session.persistentIdentifier
        )
        let messages = ProbeRuntime.eventRecorder.snapshot().filter { $0.kind == .webBridgeMessage }
        try require(messages.compactMap(\.name) == ProbeWebViewContract.phases, "exact callback inventory")
        try require(Set(messages.compactMap(\.eventID)).count == 6, "unique browser IDs")
        try require(Set(messages.compactMap { $0.webMessage?.webViewIdentity }).count == 2, "two actual callback instances")
        record("web-local-inputs-verified")
    }
    #else
    static func configure() {}
    static func start() -> ProbeStepExecutionResult {
        .rejected(reason: "WebView acceptance requires Debug instrumentation")
    }
    #endif
}

#if DEBUG
@MainActor
private final class ProbeWebContentController: WKUserContentController {
    override func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        if name == "DatadogEventBridge" {
            super.add(ProbeWebMessageObserver(downstream: scriptMessageHandler), name: name)
        } else {
            super.add(scriptMessageHandler, name: name)
        }
    }
}

@MainActor
private final class ProbeWebMessageObserver: NSObject, WKScriptMessageHandler {
    private let downstream: WKScriptMessageHandler

    init(downstream: WKScriptMessageHandler) {
        self.downstream = downstream
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let observed = ProbeWebViewAcceptance.callback(message)
        // The SDK synchronously captures the same native attachment before its queue hop.
        downstream.userContentController(userContentController, didReceive: message)
        if let observed {
            ProbeWebViewAcceptance.recordCallback(observed)
        }
    }
}
#endif
