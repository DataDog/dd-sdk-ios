/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

@_spi(Internal)
import DatadogInternal

internal final class EmbeddedContentViewRecorder: NodeRecorder {
    let identifier: UUID

    init(identifier: UUID) {
        self.identifier = identifier
    }

    func semantics(
        of view: UIView,
        with attributes: ViewAttributes,
        in context: ViewTreeRecordingContext
    ) -> NodeSemantics? {
        guard let slotID = view.dd.sessionReplaySlotID else {
            return nil
        }

        guard attributes.hide != true else {
            return nil
        }

        let wireframeID = context.ids.nodeID(view: view, nodeRecorder: self)
        context.embeddedContentViewCache.setObject(NSNumber(value: wireframeID), forKey: view)

        return SpecificElement(
            subtreeStrategy: .ignore,
            nodes: [
                .init(
                    viewAttributes: attributes,
                    wireframesBuilder: EmbeddedContentWireframesBuilder(
                        wireframeID: wireframeID,
                        slotID: slotID,
                        attributes: attributes
                    )
                )
            ]
        )
    }
}

internal struct EmbeddedContentWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID
    let slotID: String
    let attributes: ViewAttributes

    var wireframeRect: CGRect { attributes.frame }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        guard attributes.isVisible else {
            return []
        }

        return [
            builder.visibleEmbeddedContentWireframe(
                id: wireframeID,
                slotID: slotID,
                frame: attributes.frame,
                clip: attributes.clip,
                borderColor: attributes.layerBorderColor,
                borderWidth: attributes.layerBorderWidth,
                backgroundColor: attributes.backgroundColor,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}
#endif
