/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import WebKit
import SwiftUI

internal struct UnsupportedViewRecorder: NodeRecorder {
    // swiftlint:disable opening_brace
    private let unsupportedViewsPredicates: [(UIView) -> Bool] = [
        {
            if #available(iOS 13.0, *) {
                return $0 is (any View)
            } else {
                return false
            }
        },
        { $0 is UIProgressView },
        { $0 is UIWebView },
        { $0 is WKWebView },
        { $0 is UIActivityIndicatorView }
    ]
    // swiftlint:enable opening_brace
    
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard unsupportedViewsPredicates.reduce(false, { $0 || $1(view) }) else {
            return nil
        }
        guard attributes.isVisible else {
            return InvisibleElement(subtreeStrategy: .ignore)
        }
        let builder = UnsupportedViewWireframesBuilder(
            wireframeRect: view.frame,
            wireframeID: context.ids.nodeID(for: view),
            unsupportedClassName: String(describing: type(of: view)),
            attributes: attributes
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct UnsupportedViewWireframesBuilder: NodeWireframesBuilder {
    let wireframeRect: CGRect

    let wireframeID: WireframeID
    let unsupportedClassName: String
    let attributes: ViewAttributes

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createTextWireframe(
                id: wireframeID,
                frame: attributes.frame,
                text: unsupportedClassName,
                textFrame: attributes.frame,
                textAlignment: .init(horizontal: .center, vertical: .center),
                textColor: UIColor.red.cgColor,
                borderColor: UIColor.lightGray.cgColor,
                borderWidth: 1,
                backgroundColor: UIColor(white: 0, alpha: 0.05).cgColor,
                cornerRadius: 8
            )
        ]
    }
}
