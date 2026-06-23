/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal

/// Builds the composition tree produced by the layer recording pipeline.
@available(iOS 13.0, tvOS 13.0, *)
internal class CompositionTreeBuilder {
    private typealias TextInputSemantics = CALayerSnapshot.SemanticObservation.TextInputSemantics

    struct Output {
        let compositionTree: SRCompositionTree
        let wireframes: [SRWireframe]
        let resources: [Resource]
    }

    private let root: CALayerSnapshot
    private let imageSnapshotResults: [Int64: ImageSnapshotResult]
    private let webViewSlotIDs: Set<Int>

    private var layers: [SRCompositionLayer] = []
    private var wireframes: [SRWireframe] = []
    private var resources: [Resource] = []
    private var pendingWebViewSlotIDs: Set<Int> = []

    init(
        root: CALayerSnapshot,
        webViewSlotIDs: Set<Int>,
        imageSnapshotResults: [Int64: ImageSnapshotResult]
    ) {
        self.root = root
        self.webViewSlotIDs = webViewSlotIDs
        self.imageSnapshotResults = imageSnapshotResults
    }

    func build() -> Output {
        layers.removeAll(keepingCapacity: true)
        wireframes.removeAll(keepingCapacity: true)
        resources.removeAll(keepingCapacity: true)
        pendingWebViewSlotIDs = webViewSlotIDs

        let rootLayer = makeCompositionLayer(from: root, parentTextInput: nil)

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
        parentTextInput: TextInputSemantics?
    ) -> SRCompositionLayer {
        SRCompositionLayer(
            children: children(for: snapshot, parentTextInput: parentTextInput),
            compositeOperation: snapshot.compositingFilter
                .flatMap(SRCompositionLayer.CompositeOperation.init(compositingFilter:)),
            height: Int64.ddWithNoOverflow(snapshot.absoluteFrame.height),
            id: snapshot.replayID,
            modifiers: snapshot.modifiers(),
            width: Int64.ddWithNoOverflow(snapshot.absoluteFrame.width),
            x: Int64.ddWithNoOverflow(snapshot.absoluteFrame.minX),
            y: Int64.ddWithNoOverflow(snapshot.absoluteFrame.minY)
        )
    }

    private func children(
        for snapshot: CALayerSnapshot,
        parentTextInput: TextInputSemantics?
    ) -> [SRCompositionLayerChild] {
        let parentTextInput = snapshot.observation.textInputSemantics ?? parentTextInput

        guard !snapshot.sublayers.isEmpty else {
            return makeWireframeReference(for: snapshot, parentTextInput: parentTextInput)
                .map { [$0] } ?? []
        }

        var children: [SRCompositionLayerChild] = []

        // Append a wireframe for the layer background color
        // We don't support containers with image or custom content because `CALayer.render(in:)`
        // renders both the layer and its sublayers
        if snapshot.hasBackgroundColor || snapshot.hasBorder,
           let backgroundWireframe = makeWireframeReference(for: snapshot, parentTextInput: parentTextInput) {
            children.append(backgroundWireframe)
        }

        children.append(
            contentsOf: snapshot.sublayers.compactMap { sublayer in
                childReference(for: sublayer, parentTextInput: parentTextInput)
            }
        )

        return children
    }

    private func childReference(
        for snapshot: CALayerSnapshot,
        parentTextInput: TextInputSemantics?
    ) -> SRCompositionLayerChild? {
        guard !snapshot.sublayers.isEmpty || snapshot.requiresCompositionLayer else {
            return makeWireframeReference(for: snapshot, parentTextInput: parentTextInput)
        }

        let layer = makeCompositionLayer(from: snapshot, parentTextInput: parentTextInput)
        layers.append(layer)

        return .init(id: layer.id, type: .layer)
    }

    private func makeWireframeReference(
        for snapshot: CALayerSnapshot,
        parentTextInput textInput: TextInputSemantics?
    ) -> SRCompositionLayerChild? {
        let wireframe: SRWireframe? = switch (
            snapshot.observation.semantics,
            imageSnapshotResults[snapshot.replayID]
        ) {
        case (.layer, .some(let result)),
            (.activityIndicator, .some(let result)),
            (.image, .some(let result)),
            (.stepper, .some(let result)),
            (.switchControl, .some(let result)):
            makeImageSnapshotWireframe(for: snapshot, result: result, parentTextInput: textInput)
        case (.layer, .none):
            SRWireframe(layerSnapshot: snapshot)
        case (.label(let label), _):
            SRWireframe(layerSnapshot: snapshot, label: label)
        case (.textInput, .none):
            SRWireframe(layerSnapshot: snapshot)
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
            SRWireframe(layerSnapshot: snapshot)
        case (.webView(let webView), _):
            makeVisibleWebViewWireframe(for: snapshot, webView: webView)
        default:
            nil
        }

        guard let wireframe else {
            return nil
        }

        wireframes.append(wireframe)
        return SRCompositionLayerChild(id: snapshot.wireframeID, type: .wireframe)
    }

    private func makeImageSnapshotWireframe(
        for layerSnapshot: CALayerSnapshot,
        result: ImageSnapshotResult,
        parentTextInput textInput: TextInputSemantics?
    ) -> SRWireframe? {
        switch result {
        case .success(let imageSnapshot):
            do {
                switch try imageSnapshot.redacted(parentTextInput: textInput) {
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
                        placeholderColor: color
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
    var textInputSemantics: TextInputSemantics? {
        guard case .textInput(let textInput) = semantics else {
            return nil
        }
        return textInput
    }
}
#endif
