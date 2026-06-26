/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import QuartzCore
import Testing
import UIKit
import WebKit

@testable import DatadogSessionReplay

@MainActor
struct CALayerSnapshotSemanticObservationTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records plain layer semantics")
    func recordsPlainLayerSemantics() {
        // Given
        let layer = CALayer()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records activity indicator semantics and ignores sublayers")
    func recordsActivityIndicatorSemanticsAndIgnoresSublayers() {
        // Given
        let activityIndicator = UIActivityIndicatorView(style: .medium)

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: activityIndicator.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .activityIndicator, ignoreSublayers: true))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records label semantics and ignores sublayers")
    func recordsLabelSemanticsAndIgnoresSublayers() {
        // Given
        let font = UIFont.boldSystemFont(ofSize: 14)
        let label = UILabel()
        label.text = "Hello"
        label.textColor = .red
        label.textAlignment = .center
        label.font = font
        label.adjustsFontSizeToFitWidth = true
        label.lineBreakMode = .byTruncatingMiddle

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .label(
                .init(
                    text: "Hello",
                    textColor: .red,
                    textAlignment: .center,
                    font: font,
                    adjustsFontSizeToFitWidth: true,
                    lineBreakMode: .byTruncatingMiddle
                )
            ),
            ignoreSublayers: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records single run attributed label semantics")
    func recordsSingleRunAttributedLabelSemantics() {
        // Given
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: "Hello",
            attributes: [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.red
            ]
        )

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .label(
                .init(
                    text: "Hello",
                    textColor: label.textColor,
                    textAlignment: label.textAlignment,
                    font: label.font,
                    adjustsFontSizeToFitWidth: label.adjustsFontSizeToFitWidth,
                    lineBreakMode: label.lineBreakMode
                )
            ),
            ignoreSublayers: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records multi run attributed label as layer semantics")
    func recordsMultiRunAttributedLabelAsLayerSemantics() {
        // Given
        let label = UILabel()
        let attributedText = NSMutableAttributedString(string: "Hello")
        attributedText.addAttribute(.foregroundColor, value: UIColor.red, range: NSRange(location: 0, length: 2))
        attributedText.addAttribute(.foregroundColor, value: UIColor.blue, range: NSRange(location: 2, length: 3))
        label.attributedText = attributedText

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: label.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records image semantics and ignores sublayers")
    func recordsImageSemanticsAndIgnoresSublayers() {
        // Given
        let imageView = UIImageView(image: UIImage())
        imageView.isHighlighted = true

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: imageView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .image(
                .init(hasContent: true, isContextual: false)
            ),
            ignoreSublayers: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records progress view as layer semantics ignoring image privacy")
    func recordsProgressViewAsLayerSemanticsIgnoringImagePrivacy() {
        // Given
        let progressView = UIProgressView()
        progressView.progress = 0.75

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: progressView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer, ignoresImagePrivacy: true))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records slider as layer semantics ignoring image privacy")
    func recordsSliderAsLayerSemanticsIgnoringImagePrivacy() {
        // Given
        let slider = UISlider()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: slider.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer, ignoresImagePrivacy: true))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records button as layer semantics ignoring image privacy")
    func recordsButtonAsLayerSemanticsIgnoringImagePrivacy() {
        // Given
        let button = UIButton()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: button.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .layer, ignoresImagePrivacy: true))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records stepper semantics and ignores sublayers")
    func recordsStepperSemanticsAndIgnoresSublayers() {
        // Given
        let stepper = UIStepper()
        stepper.value = 7

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: stepper.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .stepper(.init(value: 7)),
            ignoreSublayers: true,
            ignoresImagePrivacy: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records text view input semantics and records sublayers")
    func recordsTextViewInputSemanticsAndRecordsSublayers() {
        // Given
        let textView = UITextView()
        textView.text = "Body"
        textView.isEditable = false
        textView.isSecureTextEntry = true

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .textInput(
            .init(
                isSensitiveText: true,
                isEditable: false,
                isEmpty: false
            )
        )))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records empty text view input semantics")
    func recordsEmptyTextViewInputSemantics() {
        // Given
        let textView = UITextView()

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .textInput(
            .init(
                isSensitiveText: false,
                isEditable: true,
                isEmpty: true
            )
        )))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records nil text view input semantics")
    func recordsNilTextViewInputSemantics() {
        // Given
        let textView = UITextView()
        textView.text = nil

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .textInput(
            .init(
                isSensitiveText: false,
                isEditable: true,
                isEmpty: true
            )
        )))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records text field input semantics and records sublayers")
    func recordsTextFieldInputSemanticsAndRecordsSublayers() {
        // Given
        let textField = UITextField()
        textField.text = "Value"
        textField.placeholder = "Placeholder"
        textField.isSecureTextEntry = true

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textField.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .textInput(
                .init(
                    isSensitiveText: true,
                    isEditable: true,
                    isEmpty: false
                )
            ),
            ignoresImagePrivacy: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records empty text field input semantics")
    func recordsEmptyTextFieldInputSemantics() {
        // Given
        let textField = UITextField()
        textField.placeholder = "Placeholder"

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textField.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .textInput(
                .init(
                    isSensitiveText: false,
                    isEditable: true,
                    isEmpty: true
                )
            ),
            ignoresImagePrivacy: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records switch semantics and ignores sublayers")
    func recordsSwitchSemanticsAndIgnoresSublayers() {
        // Given
        let switchControl = UISwitch()
        switchControl.isOn = true

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: switchControl.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .switchControl(.init(isOn: true)),
            ignoreSublayers: true,
            ignoresImagePrivacy: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records web view semantics and caches web view")
    func recordsWebViewSemanticsAndCachesWebView() {
        // Given
        let webView = WKWebView()
        let webViewCache = NSHashTable<WKWebView>.weakObjects()
        let context = CALayerSnapshot.Context.mockAny(webViewCache: webViewCache)

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: webView.layer, context: context)

        // Then
        #expect(
            observation == .init(
                semantics: .webView(.init(slotID: webView.hash, slotFrame: webView.frame)),
                ignoreSublayers: true
            )
        )
        #expect(webViewCache.allObjects.first === webView)
    }
}

#endif
