// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
import UIKit

/// Isolated fixture component. The session does not instantiate it until the
/// physical source and capture adapter have qualified independently.
@MainActor
internal final class ProbeSceneBackgroundDisplay {
    typealias Contract = ProbeSceneBackgroundDisplayContract
    typealias Surface = ProbePhysicalOperationDisplay.Surface
    struct Receipt: Encodable {
        let schemaVersion = 1
        let descriptor: Data
        let geometry: [String: [String: ProbeGeometry]]
        let geometryScope = "window-local-points-only"
        let nativeAcceptance = false
    }
    private let registry: ProbeSceneRegistry
    private let identity: Contract.Control.Identity
    private var owners: [Contract.Owner]?
    private var surfaces: [String: Surface] = [:]
    private var phase = -1
    private var inspections = 0
    private var failed = false

    init(registry: ProbeSceneRegistry, identity: Contract.Control.Identity) {
        self.registry = registry; self.identity = identity
    }

    private static func id(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }

    private func window(_ owner: Contract.Owner) throws -> UIWindow {
        guard let handle = registry.handle(logicalSceneID: owner.logicalSceneID),
              handle.nativeSceneID == owner.nativeSceneID, handle.disconnectGeneration == owner.generation,
              let window = registry.window(for: handle), let scene = window.windowScene,
              let root = window.rootViewController, scene.session.persistentIdentifier == owner.nativeSceneID,
              Self.id(scene) == owner.sceneIdentity, Self.id(window) == owner.windowIdentity,
              Self.id(root) == owner.rootIdentity, root.viewIfLoaded?.window === window else {
            throw Contract.Failure.owner
        }
        return window
    }

    func render(request: Data, witness: Data) throws -> Data {
        do {
            guard !failed else { throw Contract.Failure.sequence }
            let descriptor = try Contract.make(request: request, witness: witness, identity: identity)
            let index = try JSONDecoder().decode(ProbeSceneBackgroundPhase.Request.self, from: request).challenge.phase
            guard index == phase || index == phase + 1, owners == nil || owners == descriptor.owners else {
                throw Contract.Failure.sequence
            }
            if index != phase { inspections = 0 }
            guard inspections < 24 else { throw Contract.Failure.sequence }
            var geometry: [String: [String: ProbeGeometry]] = [:]
            for owner in descriptor.owners where descriptor.requiredScenes.contains(owner.logicalSceneID) {
                guard let payloads = descriptor.payloads[owner.logicalSceneID],
                      let ownerPayload = payloads["owner"], let phasePayload = payloads["phase"] else {
                    throw Contract.Failure.identity
                }
                let window = try window(owner)
                let ownerImage = try ProbePhysicalOperationDisplay.image(ownerPayload)
                let phaseImage = try ProbePhysicalOperationDisplay.image(phasePayload)
                let surface: Surface
                if let existing = surfaces[owner.logicalSceneID] {
                    surface = existing
                    surface.ownerImage = ownerImage; surface.phaseImage = phaseImage
                    surface.owner.image = ownerImage; surface.phase.image = phaseImage
                } else {
                    surface = Surface(window: window,
                        binding: .init(logicalSceneID: owner.logicalSceneID, nativeSceneID: owner.nativeSceneID,
                                       generation: owner.generation, windowIdentity: owner.windowIdentity,
                                       rootIdentity: owner.rootIdentity), ownerImage: ownerImage, phaseImage: phaseImage)
                    surfaces[owner.logicalSceneID] = surface
                }
                try surface.layout(); try surface.validate(in: window)
                geometry[owner.logicalSceneID] = surface.geometry()
            }
            let raw = try Contract.Control.encode(Receipt(descriptor: Contract.Control.encode(descriptor), geometry: geometry))
            owners = descriptor.owners; phase = index; inspections += 1
            return raw
        } catch { failed = true; throw error }
    }

    func retire() {
        failed = true
        for surface in surfaces.values { surface.view.removeFromSuperview() }
        surfaces.removeAll()
    }
}
