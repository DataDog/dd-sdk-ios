/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import ObjectiveC
import QuartzCore
import TestUtilities
import Testing
import UIKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct ContentSnapshotRedactionTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Returns the original image when no redaction is needed")
    func returnsOriginalImageWhenNoRedactionIsNeeded() throws {
        // Given
        let image = UIImage()
        let snapshot = ContentSnapshot.mockAny(
            image: image,
            layerClass: CALayer.self
        )

        // When
        let result = try snapshot.redacted(parentTextInput: nil)

        // Then
        let redactedImage = try #require(result.image)
        #expect(redactedImage === image)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Returns placeholder with background color when image should not be sent")
    func returnsPlaceholderWithBackgroundColorWhenImageShouldNotBeSent() throws {
        // Given
        let image = UIImage.mockWith(color: .red)
        let snapshot = ContentSnapshot.mockAny(
            image: image,
            layerClass: try imageLayerClass(),
            imagePrivacyLevel: .maskAll
        )

        // When
        let result = try snapshot.redacted(parentTextInput: nil)

        // Then
        let backgroundColor = try #require(result.placeholderColor)
        #expect(backgroundColor == .red)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not redact generic layer snapshots")
    func doesNotRedactGenericLayerSnapshots() {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            layerClass: CALayer.self,
            textAndInputPrivacyLevel: .maskAll,
            imagePrivacyLevel: .maskAll
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .none)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not redact non-layer semantic snapshots")
    func doesNotRedactNonLayerSemanticSnapshots() {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            layerClass: UIImageView.self,
            hasLayerSemantics: false,
            textAndInputPrivacyLevel: .maskAll,
            imagePrivacyLevel: .maskAll
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .none)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts sensitive non-empty text input layout fragments when masking sensitive inputs")
    func redactsSensitiveNonEmptyTextInputLayoutFragmentsWhenMaskingSensitiveInputs() throws {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            delegateClass: try textLayoutFragmentClass(),
            textAndInputPrivacyLevel: .maskSensitiveInputs
        )
        let textInput = CALayerSnapshot.SemanticObservation.TextInputSemantics(
            isSensitiveText: true,
            isEditable: true,
            isEmpty: false
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: textInput)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not redact non-sensitive text input layout fragments when masking sensitive inputs")
    func doesNotRedactNonSensitiveTextInputLayoutFragmentsWhenMaskingSensitiveInputs() throws {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            delegateClass: try textLayoutFragmentClass(),
            textAndInputPrivacyLevel: .maskSensitiveInputs
        )
        let textInput = CALayerSnapshot.SemanticObservation.TextInputSemantics(
            isSensitiveText: false,
            isEditable: true,
            isEmpty: false
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: textInput)

        // Then
        #expect(action == .none)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts non-empty text input layout fragments when masking all inputs")
    func redactsNonEmptyTextInputLayoutFragmentsWhenMaskingAllInputs() throws {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            delegateClass: try textLayoutFragmentClass(),
            textAndInputPrivacyLevel: .maskAllInputs
        )
        let textInput = CALayerSnapshot.SemanticObservation.TextInputSemantics(
            isSensitiveText: false,
            isEditable: true,
            isEmpty: false
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: textInput)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts text field canvas views when masking all inputs")
    func redactsTextFieldCanvasViewsWhenMaskingAllInputs() throws {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            delegateClass: try textFieldCanvasClass(),
            textAndInputPrivacyLevel: .maskAllInputs
        )
        let textInput = CALayerSnapshot.SemanticObservation.TextInputSemantics(
            isSensitiveText: false,
            isEditable: true,
            isEmpty: false
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: textInput)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not redact read-only text input layout fragments when masking all inputs")
    func doesNotRedactReadOnlyTextInputLayoutFragmentsWhenMaskingAllInputs() throws {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            delegateClass: try textLayoutFragmentClass(),
            textAndInputPrivacyLevel: .maskAllInputs
        )
        let textInput = CALayerSnapshot.SemanticObservation.TextInputSemantics(
            isSensitiveText: false,
            isEditable: false,
            isEmpty: false
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: textInput)

        // Then
        #expect(action == .none)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts sensitive read-only text input layout fragments when masking all inputs")
    func redactsSensitiveReadOnlyTextInputLayoutFragmentsWhenMaskingAllInputs() throws {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            delegateClass: try textLayoutFragmentClass(),
            textAndInputPrivacyLevel: .maskAllInputs
        )
        let textInput = CALayerSnapshot.SemanticObservation.TextInputSemantics(
            isSensitiveText: true,
            isEditable: false,
            isEmpty: false
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: textInput)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not redact empty text input descendants")
    func doesNotRedactEmptyTextInputDescendants() {
        // Given
        let snapshot = ContentSnapshot.mockAny(textAndInputPrivacyLevel: .maskAll)
        let textInput = CALayerSnapshot.SemanticObservation.TextInputSemantics(
            isSensitiveText: true,
            isEditable: true,
            isEmpty: true
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: textInput)

        // Then
        #expect(action == .none)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts SwiftUI drawing layers when masking all text")
    func redactsSwiftUIDrawingLayersWhenMaskingAllText() {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            layerClass: TestCGDrawingLayer.self,
            textAndInputPrivacyLevel: .maskAll
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts SwiftUI drawing view delegates when masking all text")
    func redactsSwiftUIDrawingViewDelegatesWhenMaskingAllText() {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            delegateClass: TestCGDrawingView.self,
            textAndInputPrivacyLevel: .maskAll
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts UILabel backed layers when masking all text")
    func redactsUILabelBackedLayersWhenMaskingAllText() {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            delegateClass: UILabel.self,
            textAndInputPrivacyLevel: .maskAll
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts UILabel subclass backed layers when masking all text")
    func redactsUILabelSubclassBackedLayersWhenMaskingAllText() {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            delegateClass: TestLabel.self,
            textAndInputPrivacyLevel: .maskAll
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts UILabel layers when masking all text")
    func redactsUILabelLayersWhenMaskingAllText() {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            layerClass: TestUILabelLayer.self,
            textAndInputPrivacyLevel: .maskAll
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts CATextLayer when masking all text")
    func redactsCATextLayerWhenMaskingAllText() {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            layerClass: CATextLayer.self,
            textAndInputPrivacyLevel: .maskAll
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Redacts CATextLayer subclasses when masking all text")
    func redactsCATextLayerSubclassesWhenMaskingAllText() {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            layerClass: TestTextLayer.self,
            textAndInputPrivacyLevel: .maskAll
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .redactText)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not redact static text candidates when only masking inputs")
    func doesNotRedactStaticTextCandidatesWhenOnlyMaskingInputs() {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            layerClass: CATextLayer.self,
            textAndInputPrivacyLevel: .maskAllInputs
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .none)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Uses placeholder for SwiftUI image layers when masking all images")
    func usesPlaceholderForSwiftUIImageLayersWhenMaskingAllImages() throws {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            layerClass: try imageLayerClass(),
            imagePrivacyLevel: .maskAll
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .placeholder)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not redact SwiftUI image layers when image masking is disabled")
    func doesNotRedactSwiftUIImageLayersWhenImageMaskingIsDisabled() throws {
        // Given
        let snapshot = ContentSnapshot.mockAny(
            layerClass: try imageLayerClass(),
            imagePrivacyLevel: .maskNone
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .none)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not redact small SwiftUI image layers when masking non-bundled images")
    func doesNotRedactSmallSwiftUIImageLayersWhenMaskingNonBundledImages() throws {
        // Given
        let image = UIImage(cgImage: MockCGImage.mockWith(width: 100), scale: 1, orientation: .up)
        let snapshot = ContentSnapshot.mockAny(
            image: image,
            layerClass: try imageLayerClass(),
            imagePrivacyLevel: .maskNonBundledOnly
        )

        // When
        let action = snapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(action == .none)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Uses placeholder for large SwiftUI image layers when masking non-bundled images")
    func usesPlaceholderForLargeSwiftUIImageLayersWhenMaskingNonBundledImages() throws {
        // Given
        let image = UIImage(cgImage: MockCGImage.mockWith(width: 150), scale: 1, orientation: .up)
        let maskNonBundledOnlySnapshot = ContentSnapshot.mockAny(
            image: image,
            layerClass: try imageLayerClass(),
            imagePrivacyLevel: .maskNonBundledOnly
        )

        // When
        let maskNonBundledOnlyAction = maskNonBundledOnlySnapshot.redactionAction(parentTextInput: nil)

        // Then
        #expect(maskNonBundledOnlyAction == .placeholder)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private final class TestCGDrawingLayer: CALayer {}

@available(iOS 13.0, tvOS 13.0, *)
private final class TestUILabelLayer: CALayer {}

@available(iOS 13.0, tvOS 13.0, *)
private final class TestTextLayer: CATextLayer {}

@available(iOS 13.0, tvOS 13.0, *)
private final class TestLabel: UILabel {}

@available(iOS 13.0, tvOS 13.0, *)
private final class TestCGDrawingView: UIView {}

@available(iOS 13.0, tvOS 13.0, *)
private extension ImageRedactionResult {
    var image: UIImage? {
        guard case let .image(image) = self else {
            return nil
        }

        return image
    }

    var placeholderColor: UIColor? {
        guard case let .placeholder(color) = self else {
            return nil
        }

        return color
    }
}

private func textLayoutFragmentClass() throws -> AnyClass {
    try #require(NSClassFromString("_UITextLayoutFragmentView"))
}

private func textFieldCanvasClass() throws -> AnyClass {
    try #require(NSClassFromString("_UITextFieldCanvasView"))
}

private func imageLayerClass() throws -> AnyClass {
    try #require(NSClassFromString("SwiftUI.ImageLayer"))
}

#endif
