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

    private var layers: [SRCompositionLayer] = []
    private var wireframes: [SRWireframe] = []
    private var resources: [Resource] = []

    private let compositionLayerBuilder: CompositionLayerBuilder
    private var layerWireframeBuilder: LayerWireframeBuilder

    init(
        root: CALayerSnapshot,
        webViewSlotIDs: Set<Int>,
        embeddedContentSlots: [Int64: String],
        imageSnapshots: ImageSnapshotBatch
    ) {
        self.root = root
        self.compositionLayerBuilder = CompositionLayerBuilder(
            maskSnapshots: imageSnapshots.maskSnapshots
        )
        self.layerWireframeBuilder = LayerWireframeBuilder(
            contentSnapshots: imageSnapshots.contentSnapshots,
            webViewSlotIDs: webViewSlotIDs,
            embeddedContentSlots: embeddedContentSlots
        )
    }

    func build() -> Output {
        layers.removeAll(keepingCapacity: true)
        wireframes.removeAll(keepingCapacity: true)
        resources.removeAll(keepingCapacity: true)
        layerWireframeBuilder.reset()

        let rootLayer = makeCompositionLayer(from: root, context: Context())
        let hiddenWebViewWireframes = layerWireframeBuilder.makeHiddenWebViewWireframes()
        let hiddenEmbeddedContentWireframes = layerWireframeBuilder.makeHiddenEmbeddedContentWireframes()
        let output = Output(
            compositionTree: SRCompositionTree(
                layers: layers,
                root: rootLayer
            ),
            wireframes: hiddenWebViewWireframes + hiddenEmbeddedContentWireframes + wireframes,
            resources: resources
        )

        return output
    }

    private func makeCompositionLayer(
        from snapshot: CALayerSnapshot,
        context: Context
    ) -> SRCompositionLayer {
        let output = compositionLayerBuilder.build(
            from: snapshot,
            children: children(for: snapshot, context: context)
        )

        if let resource = output.resource {
            resources.append(resource)
        }

        return output.layer
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
        if snapshot.hasBackgroundColor
            || snapshot.hasBorder
            || snapshot.observation.gradient != nil
            || snapshot.observation.semantics == .visualEffect(.automaticCapsule),
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
        guard let output = layerWireframeBuilder.build(
            from: snapshot,
            textInput: context.textInput,
            cornerRadius: context.cornerRadius(for: snapshot)
        ) else {
            return nil
        }

        if let resource = output.resource {
            resources.append(resource)
        }

        wireframes.append(output.wireframe)
        return SRCompositionLayerChild(id: output.wireframe.id, type: .wireframe)
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
