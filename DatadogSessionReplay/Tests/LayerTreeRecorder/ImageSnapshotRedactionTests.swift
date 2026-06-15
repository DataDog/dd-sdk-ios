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

struct ImageSnapshotRedactionTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not redact generic layer snapshots")
    func doesNotRedactGenericLayerSnapshots() {
        // Given
        let snapshot = ImageSnapshot.mockAny(
            layerClass: CALayer.self,
            semantics: .layer,
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
        let snapshot = ImageSnapshot.mockAny(
            layerClass: UIImageView.self,
            semantics: .image(.init(image: UIImage(), highlightedImage: nil, isHighlighted: false, tintColor: nil)),
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
        let snapshot = ImageSnapshot.mockAny(
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
        let snapshot = ImageSnapshot.mockAny(
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
        let snapshot = ImageSnapshot.mockAny(
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
    @Test("Does not redact empty text input descendants")
    func doesNotRedactEmptyTextInputDescendants() {
        // Given
        let snapshot = ImageSnapshot.mockAny(textAndInputPrivacyLevel: .maskAll)
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
        let snapshot = ImageSnapshot.mockAny(
            layerClass: TestCGDrawingLayer.self,
            semantics: .layer,
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
        let snapshot = ImageSnapshot.mockAny(
            delegateClass: TestCGDrawingView.self,
            semantics: .layer,
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
        let snapshot = ImageSnapshot.mockAny(
            delegateClass: UILabel.self,
            semantics: .layer,
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
        let snapshot = ImageSnapshot.mockAny(
            layerClass: TestUILabelLayer.self,
            semantics: .layer,
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
        let snapshot = ImageSnapshot.mockAny(
            layerClass: CATextLayer.self,
            semantics: .layer,
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
        let snapshot = ImageSnapshot.mockAny(
            layerClass: CATextLayer.self,
            semantics: .layer,
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
        let snapshot = ImageSnapshot.mockAny(
            layerClass: try imageLayerClass(),
            semantics: .layer,
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
        let snapshot = ImageSnapshot.mockAny(
            layerClass: try imageLayerClass(),
            semantics: .layer,
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
        let snapshot = ImageSnapshot.mockAny(
            image: image,
            layerClass: try imageLayerClass(),
            semantics: .layer,
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
        let maskNonBundledOnlySnapshot = ImageSnapshot.mockAny(
            image: image,
            layerClass: try imageLayerClass(),
            semantics: .layer,
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
private final class TestCGDrawingView: UIView {}

private func textLayoutFragmentClass() throws -> AnyClass {
    try #require(NSClassFromString("_UITextLayoutFragmentView"))
}

private func imageLayerClass() throws -> AnyClass {
    try #require(NSClassFromString("SwiftUI.ImageLayer"))
}
#endif
