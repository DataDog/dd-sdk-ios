/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import UIKit

/// Maps layer snapshots to wireframes and resources.
@available(iOS 13.0, tvOS 13.0, *)
internal struct LayerWireframeBuilder {
    typealias TextInputSemantics = CALayerSnapshot.SemanticObservation.TextInputSemantics

    struct Output {
        let wireframe: SRWireframe
        let resource: Resource?
    }

    private let contentSnapshots: [Int64: ContentSnapshotResult]
    private let webViewSlotIDs: Set<Int>
    private var pendingWebViewSlotIDs: Set<Int>
    private let embeddedContentSlots: [Int64: String]
    private var pendingEmbeddedContentSlots: [Int64: String]

    init(
        contentSnapshots: [Int64: ContentSnapshotResult],
        webViewSlotIDs: Set<Int>,
        embeddedContentSlots: [Int64: String] = [:]
    ) {
        self.contentSnapshots = contentSnapshots
        self.webViewSlotIDs = webViewSlotIDs
        self.pendingWebViewSlotIDs = webViewSlotIDs
        self.embeddedContentSlots = embeddedContentSlots
        self.pendingEmbeddedContentSlots = embeddedContentSlots
    }

    mutating func reset() {
        pendingWebViewSlotIDs = webViewSlotIDs
        pendingEmbeddedContentSlots = embeddedContentSlots
    }

    mutating func build(
        from snapshot: CALayerSnapshot,
        textInput: TextInputSemantics?,
        cornerRadius: CGFloat?
    ) -> Output? {
        guard !snapshot.isPrivate else {
            return Output(
                wireframe: SRWireframe(placeholderFor: snapshot, label: .hiddenPlaceholder),
                resource: nil
            )
        }

        switch (
            snapshot.observation.semantics,
            contentSnapshots[snapshot.replayID]
        ) {
        case (.layer, .some(let result)),
            (.image, .some(let result)):
            return makeContentSnapshotOutput(
                for: snapshot,
                result: result,
                textInput: textInput,
                cornerRadius: cornerRadius
            )
        case (.layer, .none):
            return SRWireframe(layerSnapshot: snapshot, cornerRadius: cornerRadius)
                .map { Output(wireframe: $0, resource: nil) }
        case (.gradient(let gradient), _):
            return SRWireframe(
                layerSnapshot: snapshot,
                backgroundGradient: SRShapeGradient(gradient: gradient),
                cornerRadius: cornerRadius
            ).map { Output(wireframe: $0, resource: nil) }
        case (.label(let label), _):
            return SRWireframe(
                layerSnapshot: snapshot,
                label: label,
                cornerRadius: cornerRadius
            ).map { Output(wireframe: $0, resource: nil) }
        case (.textInput, .none):
            return SRWireframe(layerSnapshot: snapshot, cornerRadius: cornerRadius)
                .map { Output(wireframe: $0, resource: nil) }
        case (.image(let image), .none) where image.hasContent:
            let wireframe = SRWireframe(
                placeholderFor: snapshot,
                label: snapshot.imagePrivacyLevel == .maskNonBundledOnly
                    ? .contentImagePlaceholder
                    : .imagePlaceholder
            )
            return Output(wireframe: wireframe, resource: nil)
        case (.image, .none):
            return SRWireframe(layerSnapshot: snapshot, cornerRadius: cornerRadius)
                .map { Output(wireframe: $0, resource: nil) }
        case (.webView(let webView), _):
            pendingWebViewSlotIDs.remove(webView.slotID)
            return Output(
                wireframe: SRWireframe(layerSnapshot: snapshot, webView: webView),
                resource: nil
            )
        case (.embeddedContent(let embeddedContent), _):
            pendingEmbeddedContentSlots.removeValue(forKey: snapshot.replayID)
            return Output(
                wireframe: SRWireframe(layerSnapshot: snapshot, embeddedContent: embeddedContent),
                resource: nil
            )
        case (.visualEffect(.automaticCapsule), _):
            return Output(
                wireframe: SRWireframe(
                    layerSnapshot: snapshot,
                    backgroundColor: .systemBackground,
                    cornerRadius: min(snapshot.absoluteFrame.width, snapshot.absoluteFrame.height) / 2
                ),
                resource: nil
            )
        case (.visualEffect(.glassGroup), _) where snapshot.cornerRadii != .zero:
            return Output(
                wireframe: SRWireframe(layerSnapshot: snapshot, backgroundColor: .systemBackground),
                resource: nil
            )
        case (.visualEffect(.backdrop), _):
            return Output(
                wireframe: SRWireframe(layerSnapshot: snapshot, backgroundColor: .systemBackground),
                resource: nil
            )
        case (.visualEffect(.background(let color)), _):
            return Output(
                wireframe: SRWireframe(
                    layerSnapshot: snapshot,
                    backgroundColor: color ?? .secondarySystemFill
                ),
                resource: nil
            )
        case (.visualEffect(.scrollPocket(let edge)), _):
            guard let gradient = SRShapeGradient(scrollPocketEdge: edge) else {
                return nil
            }
            return SRWireframe(layerSnapshot: snapshot, backgroundGradient: gradient)
                .map { Output(wireframe: $0, resource: nil) }
        default:
            return nil
        }
    }

    mutating func makeHiddenWebViewWireframes() -> [SRWireframe] {
        let wireframes = pendingWebViewSlotIDs.map(SRWireframe.init(hiddenWebViewSlotID:))
        pendingWebViewSlotIDs.removeAll()
        return wireframes
    }

    mutating func makeHiddenEmbeddedContentWireframes() -> [SRWireframe] {
        let wireframes = pendingEmbeddedContentSlots.map {
            SRWireframe(hiddenEmbeddedContentReplayID: $0.key, slotID: $0.value)
        }
        pendingEmbeddedContentSlots.removeAll()
        return wireframes
    }

    private func makeContentSnapshotOutput(
        for layerSnapshot: CALayerSnapshot,
        result: ContentSnapshotResult,
        textInput: TextInputSemantics?,
        cornerRadius: CGFloat?
    ) -> Output? {
        switch result {
        case .success(let imageSnapshot):
            do {
                switch try imageSnapshot.redacted(parentTextInput: textInput) {
                case .image(let image):
                    let resource = ImageSnapshotResource(image: image)
                    return Output(
                        wireframe: SRWireframe(
                            replayID: layerSnapshot.replayID,
                            imageSnapshot: imageSnapshot,
                            resource: resource
                        ),
                        resource: resource
                    )
                case .placeholder(let color):
                    return Output(
                        wireframe: SRWireframe(
                            layerSnapshot: layerSnapshot,
                            backgroundColor: color,
                            cornerRadius: cornerRadius
                        ),
                        resource: nil
                    )
                }
            } catch {
                return Output(
                    wireframe: SRWireframe(
                        placeholderFor: layerSnapshot,
                        label: .redactedPlaceholder
                    ),
                    resource: nil
                )
            }
        case .failure(.timedOut):
            return Output(
                wireframe: SRWireframe(
                    placeholderFor: layerSnapshot,
                    label: .timedOutPlaceholder
                ),
                resource: nil
            )
        case .failure(.discarded):
            return nil
        }
    }
}

private extension String {
    static let hiddenPlaceholder = "Hidden"
    static let imagePlaceholder = "Image"
    static let contentImagePlaceholder = "Content Image"
    static let timedOutPlaceholder = "Timed out"
    static let redactedPlaceholder = "Redacted"
}
#endif
