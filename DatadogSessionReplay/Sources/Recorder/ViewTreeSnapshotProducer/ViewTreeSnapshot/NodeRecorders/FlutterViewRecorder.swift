/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal class FlutterViewRecorder: NodeRecorder {
    internal let identifier: UUID

    /// `FlutterView`'s class, resolved once at runtime. `nil` when Flutter isn't embedded in the
    /// host app, in which case this recorder never matches anything.
    private static let flutterViewClass: AnyClass? = NSClassFromString("FlutterView")

    init(identifier: UUID) {
        self.identifier = identifier
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard FlutterViewRecorder.isFlutterView(view) else {
            return nil
        }

        context.flutterViewCache.add(view)

        let builder = FlutterViewWireframesBuilder(slotID: view.hash, attributes: attributes)
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }

    private static func isFlutterView(_ view: UIView) -> Bool {
        guard let flutterViewClass = flutterViewClass else {
            return false
        }
        return view.isKind(of: flutterViewClass)
    }
}

internal struct FlutterViewWireframesBuilder: NodeWireframesBuilder {
    let slotID: Int
    let attributes: ViewAttributes

    var wireframeRect: CGRect { attributes.frame }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        guard attributes.isVisible else {
            // ignore hidden webview, the wireframes will be built
            // for hidden slot
            return []
        }

        return [
            builder.visibleEmbeddedContentWireframe(
                id: slotID,
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
