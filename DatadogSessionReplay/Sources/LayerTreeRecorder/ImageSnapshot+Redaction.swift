/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore
import UIKit

/// Redaction to apply to a rendered image snapshot.
@available(iOS 13.0, tvOS 13.0, *)
internal enum ImageRedactionAction: Hashable {
    case none
    case redactText
    case redactFaces
    case placeholder
}

@available(iOS 13.0, tvOS 13.0, *)
extension ImageSnapshot {
    func redactionAction(
        parentTextInput: CALayerSnapshot.SemanticObservation.TextInputSemantics?
    ) -> ImageRedactionAction {
        guard case .layer = semantics else {
            return .none
        }

        if isImageLayer && imagePrivacyLevel == .maskAll {
            return .placeholder
        }

        if shouldRedactText(parentTextInput: parentTextInput) {
            return .redactText
        }

        if isImageLayer {
            return .redactFaces
        }

        return .none
    }

    private func shouldRedactText(
        parentTextInput: CALayerSnapshot.SemanticObservation.TextInputSemantics?
    ) -> Bool {
        if let parentTextInput, isTextLayoutFragment {
            guard !parentTextInput.isEmpty else {
                return false
            }

            switch textAndInputPrivacyLevel {
            case .maskSensitiveInputs:
                return parentTextInput.isSensitiveText
            case .maskAllInputs, .maskAll:
                return true
            }
        }

        return textAndInputPrivacyLevel == .maskAll && isStaticText
    }

    private var isTextLayoutFragment: Bool {
        delegateClassName == "_UITextLayoutFragmentView" ||
        delegateClassName == "_UITextViewCanvasView"
    }

    private var isStaticText: Bool {
        layerClass == CATextLayer.self ||
        layerClassName.hasSuffix("CGDrawingLayer") ||
        layerClassName.hasSuffix("UILabelLayer") ||
        delegateClass == UILabel.self ||
        delegateClassName?.hasSuffix("CGDrawingView") == true
    }

    private var isImageLayer: Bool {
        layerClassName == "SwiftUI.ImageLayer"
    }

    private var layerClassName: String {
        NSStringFromClass(layerClass)
    }

    private var delegateClassName: String? {
        delegateClass.map(NSStringFromClass)
    }
}
#endif
