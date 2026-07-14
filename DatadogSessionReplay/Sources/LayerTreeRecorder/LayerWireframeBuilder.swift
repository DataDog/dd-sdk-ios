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
        let id: Int64
        let wireframe: SRWireframe
        let resource: Resource?
    }

    private let contentSnapshots: [Int64: ContentSnapshotResult]
    private let webViewSlotIDs: Set<Int>
    private var pendingWebViewSlotIDs: Set<Int>

    init(
        contentSnapshots: [Int64: ContentSnapshotResult],
        webViewSlotIDs: Set<Int>
    ) {
        self.contentSnapshots = contentSnapshots
        self.webViewSlotIDs = webViewSlotIDs
        self.pendingWebViewSlotIDs = webViewSlotIDs
    }

    mutating func reset() {
        pendingWebViewSlotIDs = webViewSlotIDs
    }

    mutating func build(
        from snapshot: CALayerSnapshot,
        textInput: TextInputSemantics?,
        cornerRadius: CGFloat?
    ) -> Output? {
        guard !snapshot.isPrivate else {
            return Output(
                id: snapshot.replayID,
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
                .map { Output(id: snapshot.replayID, wireframe: $0, resource: nil) }
        case (.gradient(let gradient), _):
            return SRWireframe(
                layerSnapshot: snapshot,
                gradient: gradient,
                cornerRadius: cornerRadius
            ).map { Output(id: snapshot.replayID, wireframe: $0, resource: nil) }
        case (.label(let label), _):
            return SRWireframe(
                layerSnapshot: snapshot,
                label: label,
                cornerRadius: cornerRadius
            ).map { Output(id: snapshot.replayID, wireframe: $0, resource: nil) }
        case (.textInput, .none):
            return SRWireframe(layerSnapshot: snapshot, cornerRadius: cornerRadius)
                .map { Output(id: snapshot.replayID, wireframe: $0, resource: nil) }
        case (.image(let image), .none) where image.hasContent:
            let wireframe = SRWireframe(
                placeholderFor: snapshot,
                label: snapshot.imagePrivacyLevel == .maskNonBundledOnly
                    ? .contentImagePlaceholder
                    : .imagePlaceholder
            )
            return Output(id: snapshot.replayID, wireframe: wireframe, resource: nil)
        case (.image, .none):
            return SRWireframe(layerSnapshot: snapshot, cornerRadius: cornerRadius)
                .map { Output(id: snapshot.replayID, wireframe: $0, resource: nil) }
        case (.webView(let webView), _):
            pendingWebViewSlotIDs.remove(webView.slotID)
            return Output(
                id: Int64(webView.slotID),
                wireframe: SRWireframe(layerSnapshot: snapshot, webView: webView),
                resource: nil
            )
        case (.visualEffect(.automaticCapsule), _):
            return Output(
                id: snapshot.replayID,
                wireframe: SRWireframe(
                    layerSnapshot: snapshot,
                    backgroundColor: .systemBackground,
                    cornerRadius: min(snapshot.absoluteFrame.width, snapshot.absoluteFrame.height) / 2
                ),
                resource: nil
            )
        case (.visualEffect(.glassGroup), _) where snapshot.cornerRadii != .zero:
            return Output(
                id: snapshot.replayID,
                wireframe: SRWireframe(layerSnapshot: snapshot, backgroundColor: .systemBackground),
                resource: nil
            )
        case (.visualEffect(.backdrop), _):
            return Output(
                id: snapshot.replayID,
                wireframe: SRWireframe(layerSnapshot: snapshot, backgroundColor: .systemBackground),
                resource: nil
            )
        case (.visualEffect(.background(let color)), _):
            return Output(
                id: snapshot.replayID,
                wireframe: SRWireframe(
                    layerSnapshot: snapshot,
                    backgroundColor: color ?? .secondarySystemFill
                ),
                resource: nil
            )
        default:
            return nil
        }
    }

    mutating func makeHiddenWebViewWireframes() -> [SRWireframe] {
        let wireframes = pendingWebViewSlotIDs.map(SRWireframe.init(hiddenWebViewSlotID:))
        pendingWebViewSlotIDs.removeAll()
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
                        id: layerSnapshot.replayID,
                        wireframe: SRWireframe(
                            id: layerSnapshot.replayID,
                            imageSnapshot: imageSnapshot,
                            resource: resource
                        ),
                        resource: resource
                    )
                case .placeholder(let color):
                    return Output(
                        id: layerSnapshot.replayID,
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
                    id: layerSnapshot.replayID,
                    wireframe: SRWireframe(
                        placeholderFor: layerSnapshot,
                        label: .redactedPlaceholder
                    ),
                    resource: nil
                )
            }
        case .failure(.timedOut):
            return Output(
                id: layerSnapshot.replayID,
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
