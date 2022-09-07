/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal struct UIViewRecorder: NodeRecorder {
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeSnapshotBuilder.Context) -> NodeSemantics? {
        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let builder = UIViewWireframesBuilder(attributes: attributes)
        return AmbiguousElement(wireframesBuilder: builder)
    }
}

internal struct UIViewWireframesBuilder: NodeWireframesBuilder {
    /// Attributes of the `UIView`.
    let attributes: ViewAttributes

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createShapeWireframe(
                frame: attributes.frame,
                borderColor: attributes.layerBorderColor,
                borderWidth: attributes.layerBorderWidth,
                backgroundColor: attributes.backgroundColor,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}
