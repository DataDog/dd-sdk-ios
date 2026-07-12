/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
import DatadogInternal

/// Builds the composition tree produced by the layer recording pipeline.
@available(iOS 13.0, tvOS 13.0, *)
internal class CompositionTreeBuilder {
    private typealias TextInputSemantics = CALayerSnapshot.SemanticObservation.TextInputSemantics
    private typealias VisualEffect = CALayerSnapshot.SemanticObservation.VisualEffect

    private struct Context {
        var textInput: TextInputSemantics?
        var visualEffects: [VisualEffect] = []

        mutating func merge(_ observation: CALayerSnapshot.SemanticObservation) {
            if let textInput = observation.textInputSemantics {
                self.textInput = textInput
            }

            if let visualEffect = observation.visualEffect {
                visualEffects.append(visualEffect)
            }
        }

        func cornerRadius(for snapshot: CALayerSnapshot) -> CGFloat? {
            guard
                snapshot.cornerRadii == .zero,
                visualEffects.contains(.liquidLens)
            else {
                return nil
            }

            return min(snapshot.absoluteFrame.width, snapshot.absoluteFrame.height) / 2
        }
    }

    struct Output {
        let compositionTree: SRCompositionTree
        let wireframes: [SRWireframe]
        let resources: [Resource]
    }

    private let root: CALayerSnapshot
    private let imageSnapshots: ImageSnapshotBatch
    private let webViewSlotIDs: Set<Int>

    private var layers: [SRCompositionLayer] = []
    private var wireframes: [SRWireframe] = []
    private var resources: [Resource] = []
    private var pendingWebViewSlotIDs: Set<Int> = []

    init(
        root: CALayerSnapshot,
        webViewSlotIDs: Set<Int>,
        imageSnapshots: ImageSnapshotBatch
    ) {
        self.root = root
        self.webViewSlotIDs = webViewSlotIDs
        self.imageSnapshots = imageSnapshots
    }

    func build() -> Output {
        layers.removeAll(keepingCapacity: true)
        wireframes.removeAll(keepingCapacity: true)
        resources.removeAll(keepingCapacity: true)
        pendingWebViewSlotIDs = webViewSlotIDs

        let rootLayer = makeCompositionLayer(from: root, context: Context())

        return Output(
            compositionTree: SRCompositionTree(
                layers: layers,
                root: rootLayer
            ),
            wireframes: makeHiddenWebViewWireframes() + wireframes,
            resources: resources
        )
    }

    private func makeCompositionLayer(
        from snapshot: CALayerSnapshot,
        context: Context
    ) -> SRCompositionLayer {
        var maskImage: (any SessionReplayResource)?

        if let mask = snapshot.mask, case .success(let maskSnapshot) = imageSnapshots.maskSnapshots[mask.replayID] {
            let resource = ImageSnapshotResource(image: maskSnapshot.image)
            resources.append(resource)
            maskImage = resource
        }

        return SRCompositionLayer(
            children: children(for: snapshot, context: context),
            compositeOperation: snapshot.compositingFilter
                .flatMap(SRCompositionLayer.CompositeOperation.init(compositingFilter:)),
            height: Int64.ddWithNoOverflow(dimension: snapshot.absoluteFrame.height),
            id: snapshot.replayID,
            modifiers: snapshot.modifiers(maskImageResourceID: maskImage?.calculateIdentifier()),
            width: Int64.ddWithNoOverflow(dimension: snapshot.absoluteFrame.width),
            x: Int64.ddWithNoOverflow(snapshot.absoluteFrame.minX),
            y: Int64.ddWithNoOverflow(snapshot.absoluteFrame.minY)
        )
    }

    private func children(
        for snapshot: CALayerSnapshot,
        context: Context
    ) -> [SRCompositionLayerChild] {
        var context = context
        context.merge(snapshot.observation)

        guard !snapshot.sublayers.isEmpty else {
            return makeWireframeReference(for: snapshot, context: context)
                .map { [$0] } ?? []
        }

        var children: [SRCompositionLayerChild] = []

        // Append a wireframe for the layer background, gradient, or border
        // We don't support containers with image or custom content because `CALayer.render(in:)`
        // renders both the layer and its sublayers
        if snapshot.hasBackgroundColor || snapshot.hasBorder || snapshot.observation.gradient != nil,
           let backgroundWireframe = makeWireframeReference(for: snapshot, context: context) {
            children.append(backgroundWireframe)
        }

        children.append(
            contentsOf: snapshot.sublayers.compactMap { sublayer in
                childReference(for: sublayer, context: context)
            }
        )

        return children
    }

    private func childReference(
        for snapshot: CALayerSnapshot,
        context: Context
    ) -> SRCompositionLayerChild? {
        guard !snapshot.sublayers.isEmpty || snapshot.requiresCompositionLayer else {
            return makeWireframeReference(for: snapshot, context: context)
        }

        let layer = makeCompositionLayer(from: snapshot, context: context)
        layers.append(layer)

        return .init(id: layer.id, type: .layer)
    }

    private func makeWireframeReference(
        for snapshot: CALayerSnapshot,
        context: Context
    ) -> SRCompositionLayerChild? {
        guard !snapshot.isPrivate else {
            wireframes.append(SRWireframe(placeholderFor: snapshot, label: .hiddenPlaceholder))
            return SRCompositionLayerChild(id: snapshot.wireframeID, type: .wireframe)
        }

        let cornerRadius = context.cornerRadius(for: snapshot)

        let wireframe: SRWireframe? = switch (
            snapshot.observation.semantics,
            imageSnapshots.contentSnapshots[snapshot.replayID]
        ) {
        case (.layer, .some(let result)),
            (.image, .some(let result)),
            (.visualEffect(.portal), .some(let result)):
            makeContentSnapshotWireframe(for: snapshot, result: result, context: context)
        case (.layer, .none):
            SRWireframe(layerSnapshot: snapshot, cornerRadius: cornerRadius)
        case (.gradient(let gradient), _):
            SRWireframe(
                layerSnapshot: snapshot,
                gradient: gradient,
                cornerRadius: cornerRadius
            )
        case (.label(let label), _):
            SRWireframe(layerSnapshot: snapshot, label: label, cornerRadius: cornerRadius)
        case (.textInput, .none):
            SRWireframe(layerSnapshot: snapshot, cornerRadius: cornerRadius)
        case (.image(let image), .none) where image.hasContent:
            // Private image
            SRWireframe(
                placeholderFor: snapshot,
                label: snapshot.imagePrivacyLevel == .maskNonBundledOnly
                    ? .contentImagePlaceholder
                    : .imagePlaceholder
            )
        case (.image, .none):
            // Empty image
            SRWireframe(layerSnapshot: snapshot, cornerRadius: cornerRadius)
        case (.webView(let webView), _):
            makeVisibleWebViewWireframe(for: snapshot, webView: webView)
        case (.visualEffect(.glassGroup), _) where snapshot.cornerRadii != .zero:
            SRWireframe(layerSnapshot: snapshot, backgroundColor: .systemBackground)
        case (.visualEffect(.backdrop), _):
            SRWireframe(layerSnapshot: snapshot, backgroundColor: .systemBackground)
        case (.visualEffect(.background(let color)), _):
            SRWireframe(layerSnapshot: snapshot, backgroundColor: color ?? .secondarySystemFill)
        default:
            nil
        }

        guard let wireframe else {
            return nil
        }

        wireframes.append(wireframe)
        return SRCompositionLayerChild(id: snapshot.wireframeID, type: .wireframe)
    }

    private func makeContentSnapshotWireframe(
        for layerSnapshot: CALayerSnapshot,
        result: ContentSnapshotResult,
        context: Context
    ) -> SRWireframe? {
        switch result {
        case .success(let imageSnapshot):
            do {
                switch try imageSnapshot.redacted(parentTextInput: context.textInput) {
                case .image(let image):
                    let resource = ImageSnapshotResource(image: image)
                    resources.append(resource)

                    return SRWireframe(
                        id: layerSnapshot.replayID,
                        imageSnapshot: imageSnapshot,
                        resource: resource
                    )
                case .placeholder(let color):
                    return SRWireframe(
                        layerSnapshot: layerSnapshot,
                        backgroundColor: color,
                        cornerRadius: context.cornerRadius(for: layerSnapshot)
                    )
                }
            } catch {
                return SRWireframe(
                    placeholderFor: layerSnapshot,
                    label: .redactedPlaceholder
                )
            }
        case .failure(.timedOut):
            return SRWireframe(
                placeholderFor: layerSnapshot,
                label: .timedOutPlaceholder
            )
        case .failure(.discarded):
            return nil
        }
    }

    private func makeVisibleWebViewWireframe(
        for layerSnapshot: CALayerSnapshot,
        webView: CALayerSnapshot.SemanticObservation.WebViewSemantics
    ) -> SRWireframe {
        let wireframe = SRWireframe(layerSnapshot: layerSnapshot, webView: webView)
        pendingWebViewSlotIDs.remove(webView.slotID)
        return wireframe
    }

    private func makeHiddenWebViewWireframes() -> [SRWireframe] {
        let result = pendingWebViewSlotIDs.map(SRWireframe.init(hiddenWebViewSlotID:))
        pendingWebViewSlotIDs.removeAll()
        return result
    }
}

extension String {
    fileprivate static let hiddenPlaceholder = "Hidden"
    fileprivate static let imagePlaceholder = "Image"
    fileprivate static let contentImagePlaceholder = "Content Image"
    fileprivate static let timedOutPlaceholder = "Timed out"
    fileprivate static let redactedPlaceholder = "Redacted"
}

@available(iOS 13.0, tvOS 13.0, *)
private extension CALayerSnapshot {
    var wireframeID: Int64 {
        switch observation.semantics {
        case .webView(let webView):
            return Int64(webView.slotID)
        default:
            return replayID
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension CALayerSnapshot.SemanticObservation {
    var gradient: GradientSemantics? {
        guard case .gradient(let gradient) = semantics else {
            return nil
        }
        return gradient
    }

    var textInputSemantics: TextInputSemantics? {
        guard case .textInput(let textInput) = semantics else {
            return nil
        }
        return textInput
    }

    var visualEffect: CALayerSnapshot.SemanticObservation.VisualEffect? {
        guard case .visualEffect(let visualEffect) = semantics else {
            return nil
        }
        return visualEffect
    }
}
#endif
