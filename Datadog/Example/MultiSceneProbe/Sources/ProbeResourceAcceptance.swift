/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
#if DEBUG
@_spi(Experimental)
@_spi(objc)
@testable import DatadogRUM
@_spi(Internal)
import DatadogInternal
#endif

enum ProbeResourceAcceptance {
    static let scenarioID = ProbeResourceContract.scenarioID
    static let host = "resource-probe.invalid"
    static let manualSuccess = ProbeResourceContract.manualSuccess
    static let manualFailure = ProbeResourceContract.manualFailure
    static let automatic = ProbeResourceContract.automatic
    static let legacy = ProbeResourceContract.legacy
    static let peerAction = ProbeResourceContract.peerAction
    static let completed = ProbeResourceContract.completed

    static func attributes(for request: URLRequest) -> [String: Encodable] {
        guard request.url?.host == host, let phase = request.url?.lastPathComponent else { return [:] }
        return [
            ProbeRuntime.Attribute.runID: ProbeRuntime.runID,
            ProbeRuntime.Attribute.sourceScene: "scene-A",
            ProbeRuntime.Attribute.screen: "home",
            ProbeRuntime.Attribute.phase: phase,
            "probe.resource.api": "automatic",
        ]
    }

    #if DEBUG
    @MainActor private static var running = false

    @MainActor
    static func start() -> ProbeStepExecutionResult {
        guard !running else { return .rejected(reason: "Resource batch already started") }
        running = true
        Task { @MainActor in
            do {
                try await run()
                record(completed)
            } catch {
                record(completed, result: .fail, reason: String(describing: error))
            }
        }
        return .accepted
    }

    private enum FixtureError: Error {
        case missing(String)
    }

    @MainActor
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw FixtureError.missing(message) }
    }

    @MainActor
    private static func scene(_ label: String) throws -> UIWindowScene {
        guard let handle = ProbeRuntime.sceneRegistry.handle(logicalSceneID: label),
              let scene = ProbeRuntime.sceneRegistry.window(for: handle)?.windowScene else {
            throw FixtureError.missing("native scene " + label)
        }
        return scene
    }

    @MainActor
    private static func record(
        _ name: String,
        context: RUMCoreContext? = nil,
        result: ProbeSemanticResultState = .pass,
        reason: String? = nil
    ) {
        ProbeRuntime.eventRecorder.record(ProbeSignal(
            kind: .assertion,
            evidenceSource: context == nil ? .probe : .internalHook,
            rumContext: context.map {
                ProbeRUMContext(sessionID: $0.sessionID, viewID: $0.viewID, viewName: $0.viewName, viewURL: $0.viewPath)
            },
            name: name,
            result: result,
            reason: reason
        ))
    }

    @MainActor
    private static func waitFor(_ name: String, _ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw FixtureError.missing("deadline: " + name)
    }

    @MainActor
    private static func run() async throws {
        let sceneA = try scene("scene-A")
        let sceneB = try scene("scene-B")
        try require(sceneA !== sceneB, "two distinct native scenes")
        guard let monitor = RUMMonitor.shared() as? Monitor,
              let ownerA = monitor.rumContextSnapshot(for: .scene(RUMSceneIdentifier(rawValue: sceneA.session.persistentIdentifier))),
              let ownerB = monitor.rumContextSnapshot(for: .scene(RUMSceneIdentifier(rawValue: sceneB.session.persistentIdentifier))) else {
            throw FixtureError.missing("both current SDK owners")
        }
        let targetA = RUMViewTarget.current(in: sceneA)
        let targetB = RUMViewTarget.current(in: sceneB)
        let objcTargetA = objc_RUMViewTarget.current(in: sceneA)
        let objc = objc_RUMMonitor(swiftRUMMonitor: monitor)
        let allPhases = manualSuccess + manualFailure + automatic + [legacy]
        func url(_ phase: String) -> URL {
            URL(string: "https://" + host)!.appendingPathComponent(ProbeRuntime.runID).appendingPathComponent(phase)
        }
        func key(_ phase: String) -> String { ProbeRuntime.runID + "-" + phase }
        func attributes(_ phase: String) -> [String: Encodable] {
            [
                ProbeRuntime.Attribute.runID: ProbeRuntime.runID,
                ProbeRuntime.Attribute.sourceScene: "scene-A",
                ProbeRuntime.Attribute.sceneSessionID: sceneA.session.persistentIdentifier,
                ProbeRuntime.Attribute.screen: "home",
                ProbeRuntime.Attribute.phase: phase,
                "probe.resource.api": phase.contains("objc") ? "objc" : "swift",
            ]
        }

        // The source marker is explicitly B; Resource starts must leave B representative.
        monitor.addAction(type: .custom, name: "resource-representative-b", view: targetB, attributes: [
            ProbeRuntime.Attribute.phase: "resource-representative-b",
            ProbeRuntime.Attribute.sourceScene: "scene-B",
        ])
        try require(monitor.rumContextSnapshot(for: .processRepresentative)?.viewID == ownerB.viewID, "B representative before starts")
        record("resource-owner-a", context: ownerA)
        record("resource-owner-b", context: ownerB)
        for phase in manualSuccess + manualFailure {
            record("resource-start-" + phase, context: ownerA)
            var request = URLRequest(url: url(phase))
            request.httpMethod = "POST"
            RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerB, sceneIdentifier: sceneB.session.persistentIdentifier) {
                switch phase {
                case manualSuccess[0]:
                    monitor.startResource(resourceKey: key(phase), request: request, view: targetA, attributes: attributes(phase))
                case manualSuccess[1]:
                    monitor.startResource(resourceKey: key(phase), url: url(phase), view: targetA, attributes: attributes(phase))
                case manualSuccess[2]:
                    monitor.startResource(resourceKey: key(phase), httpMethod: .put, urlString: url(phase).absoluteString, view: targetA, attributes: attributes(phase))
                case manualFailure[0]:
                    objc.startResource(resourceKey: key(phase), request: request, view: objcTargetA, attributes: attributes(phase))
                case manualFailure[1]:
                    objc.startResource(resourceKey: key(phase), url: url(phase), view: objcTargetA, attributes: attributes(phase))
                default:
                    objc.startResource(resourceKey: key(phase), httpMethod: .put, urlString: url(phase).absoluteString, view: objcTargetA, attributes: attributes(phase))
                }
            }
            try require(monitor.rumContextSnapshot(for: .processRepresentative)?.viewID == ownerB.viewID, "Resource changed representative")
        }
        record("resource-start-" + legacy, context: ownerB)
        monitor.startResource(resourceKey: key(legacy), url: url(legacy), attributes: attributes(legacy))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProbeResourceURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for phase in automatic {
            record("resource-start-" + phase, context: ownerA)
            RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerA, sceneIdentifier: sceneA.session.persistentIdentifier) {
                session.dataTask(with: url(phase)) { _, _, _ in
                    ProbeRuntime.eventRecorder.record(ProbeSignal(kind: .assertion, name: "transport-finished-" + phase, result: .pass))
                }.resume()
            }
        }
        try await waitFor("both URLSession requests paused") {
            automatic.allSatisfy { ProbeResourceURLProtocol.isPending(url($0)) }
        }
        record("resource-all-started")
        try require(ProbeRuntime.eventRecorder.snapshot().filter {
            ($0.kind == .rumResource || $0.kind == .rumError) && allPhases.contains($0.name ?? "")
        }.isEmpty, "completion occurred before release")

        func viewAttributes(_ scene: UIWindowScene, label: String, screen: String) -> [String: Encodable] {
            [
                ProbeRuntime.Attribute.runID: ProbeRuntime.runID,
                ProbeRuntime.Attribute.viewScene: label,
                ProbeRuntime.Attribute.viewSceneSessionID: scene.session.persistentIdentifier,
                ProbeRuntime.Attribute.viewScreen: screen,
            ]
        }
        monitor.startView(key: "resource-next-a", name: "Resource Next A", in: sceneA,
                          attributes: viewAttributes(sceneA, label: "scene-A", screen: "resource-next"))
        record("resource-navigation-finished")
        monitor.stopSession()
        monitor.startView(key: "resource-new-a", name: "Resource New A", in: sceneA,
                          attributes: viewAttributes(sceneA, label: "scene-A", screen: "resource-new"))
        monitor.startView(key: "resource-new-b", name: "Resource New B", in: sceneB,
                          attributes: viewAttributes(sceneB, label: "scene-B", screen: "resource-new"))
        guard let newB = monitor.rumContextSnapshot(for: .scene(RUMSceneIdentifier(rawValue: sceneB.session.persistentIdentifier))) else {
            throw FixtureError.missing("new B")
        }
        try require(newB.sessionID != ownerA.sessionID && newB.viewID != ownerB.viewID, "fresh session and B")
        record("resource-new-owner-b", context: newB)
        monitor.startAction(type: .tap, name: "resource-live-peer", view: targetB, attributes: [
            ProbeRuntime.Attribute.phase: "resource-live-peer",
            ProbeRuntime.Attribute.sourceScene: "scene-B",
        ])
        record("resource-release-boundary")
        for phase in manualSuccess + [legacy] {
            monitor.stopResource(resourceKey: key(phase), statusCode: 201, kind: .native, size: 55,
                                 attributes: ["probe.resource.completed": true])
            monitor.stopResource(resourceKey: key(phase), statusCode: 201, kind: .native)
        }
        for phase in manualFailure {
            if phase == manualFailure[0] {
                monitor.stopResourceWithError(resourceKey: key(phase), error: URLError(.networkConnectionLost),
                                              response: nil, attributes: ["probe.resource.completed": true])
            } else {
                monitor.stopResourceWithError(resourceKey: key(phase), message: "Expected fixture failure", type: "ResourceFixture",
                                              response: nil, attributes: ["probe.resource.completed": true])
            }
        }
        try require(ProbeResourceURLProtocol.release(url(automatic[0]), fails: false), "success release")
        try await waitFor("automatic success before error release") {
            ProbeRuntime.eventRecorder.snapshot().contains { $0.kind == .rumResource && $0.name == automatic[0] }
        }
        try require(ProbeResourceURLProtocol.release(url(automatic[1]), fails: true), "error release")
        try await waitFor("all Resource completions") {
            ProbeRuntime.eventRecorder.snapshot().filter {
                ($0.kind == .rumResource || $0.kind == .rumError) && allPhases.contains($0.name ?? "")
            }.count >= allPhases.count
        }
        let events = ProbeRuntime.eventRecorder.snapshot().filter {
            ($0.kind == .rumResource || $0.kind == .rumError) && allPhases.contains($0.name ?? "")
        }
        for phase in allPhases {
            let matching = events.filter { $0.name == phase }
            let owner = phase == legacy ? ownerB : ownerA
            try require(matching.count == 1, "exact completion count: " + phase)
            try require(matching[0].rumContext?.viewID == owner.viewID && matching[0].rumContext?.sessionID == owner.sessionID,
                        "captured owner: " + phase)
            let isError = manualFailure.contains(phase) || phase == automatic[1]
            try require(matching[0].kind == (isError ? .rumError : .rumResource), "completion kind: " + phase)
        }
        monitor.stopAction(type: .tap, name: peerAction, view: targetB, attributes: [
            ProbeRuntime.Attribute.phase: peerAction,
            ProbeRuntime.Attribute.sourceScene: "scene-B",
        ])
        try await waitFor("peer action") {
            ProbeRuntime.eventRecorder.snapshot().contains { $0.kind == .rumAction && $0.name == peerAction }
        }
        let peer = ProbeRuntime.eventRecorder.snapshot().filter { $0.kind == .rumAction && $0.name == peerAction }
        try require(peer.count == 1, "one peer action")
        try require(peer[0].rumContext?.viewID == newB.viewID && peer[0].rumContext?.sessionID == newB.sessionID, "new peer action owner")
        try require(peer[0].action?.resourceCount == 0 && peer[0].action?.errorCount == 0, "no old Resource counts on new action")
        record("resource-local-owners-verified")
    }
    #endif
}

#if DEBUG
private final class ProbeResourceURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var pending: [String: ProbeResourceURLProtocol] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == ProbeResourceAcceptance.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let key = request.url?.absoluteString else { return }
        Self.lock.lock()
        Self.pending[key] = self
        Self.lock.unlock()
        ProbeRuntime.eventRecorder.record(ProbeSignal(kind: .assertion, name: "transport-paused-" + (request.url?.lastPathComponent ?? ""), result: .pass))
    }

    override func stopLoading() {
        guard let key = request.url?.absoluteString else { return }
        Self.lock.lock()
        if Self.pending[key] === self { Self.pending.removeValue(forKey: key) }
        Self.lock.unlock()
    }

    static func isPending(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending[url.absoluteString] != nil
    }

    static func release(_ url: URL, fails: Bool) -> Bool {
        lock.lock()
        let loader = pending.removeValue(forKey: url.absoluteString)
        lock.unlock()
        guard let loader, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                        headerFields: ["Content-Type": "application/json"]) else { return false }
        loader.client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed)
        loader.client?.urlProtocol(loader, didLoad: Data("{}".utf8))
        if fails {
            loader.client?.urlProtocol(loader, didFailWithError: URLError(.networkConnectionLost))
        } else {
            loader.client?.urlProtocolDidFinishLoading(loader)
        }
        return true
    }
}
#endif
