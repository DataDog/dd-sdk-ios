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
    case placeholder
}

/// Redacted image or placeholder instruction.
@available(iOS 13.0, tvOS 13.0, *)
internal enum ImageRedactionResult {
    case image(UIImage)
    case placeholder(UIColor)
}

@available(iOS 13.0, tvOS 13.0, *)
extension ImageSnapshot {
    func redacted(
        parentTextInput: CALayerSnapshot.SemanticObservation.TextInputSemantics?
    ) throws -> ImageRedactionResult {
        switch redactionAction(parentTextInput: parentTextInput) {
        case .none:
            return .image(image)
        case .redactText:
            return .image(try image.redactingText())
        case .placeholder:
            return .placeholder(image.redactionColor)
        }
    }

    func redactionAction(
        parentTextInput: CALayerSnapshot.SemanticObservation.TextInputSemantics?
    ) -> ImageRedactionAction {
        guard hasLayerSemantics else {
            return .none
        }

        if isImageLayer {
            return imageLayerRedactionAction
        }

        if shouldRedactText(parentTextInput: parentTextInput) {
            return .redactText
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
            case .maskAllInputs:
                return parentTextInput.isSensitiveText || parentTextInput.isEditable
            case .maskAll:
                return true
            }
        }

        return textAndInputPrivacyLevel == .maskAll && isStaticText
    }

    private var isTextLayoutFragment: Bool {
        delegateClassName == "_UITextLayoutFragmentView" ||
        delegateClassName == "_UITextViewCanvasView" ||
        delegateClassName == "_UITextFieldCanvasView"
    }

    private var isStaticText: Bool {
        layerClass.isSubclass(of: CATextLayer.self) ||
        layerClassName.hasSuffix("CGDrawingLayer") ||
        layerClassName.hasSuffix("UILabelLayer") ||
        delegateClass?.isSubclass(of: UILabel.self) == true ||
        delegateClassName?.hasSuffix("CGDrawingView") == true
    }

    private var isImageLayer: Bool {
        layerClassName == "SwiftUI.ImageLayer"
    }

    private var imageLayerRedactionAction: ImageRedactionAction {
        switch imagePrivacyLevel {
        case .maskNone:
            return .none
        case .maskNonBundledOnly:
            guard let cgImage = image.cgImage else {
                return .placeholder
            }
            return cgImage.isLikelyBundled(scale: image.scale) ? .none : .placeholder
        case .maskAll:
            return .placeholder
        }
    }

    private var layerClassName: String {
        NSStringFromClass(layerClass)
    }

    private var delegateClassName: String? {
        delegateClass.map(NSStringFromClass)
    }
}
#endif
