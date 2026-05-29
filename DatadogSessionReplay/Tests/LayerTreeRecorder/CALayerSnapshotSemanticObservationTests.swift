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
    @Test("Records activity indicator semantics and ignores subtree")
    func recordsActivityIndicatorSemanticsAndIgnoresSubtree() {
        // Given
        let activityIndicator = UIActivityIndicatorView(style: .medium)

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: activityIndicator.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .activityIndicator, ignoreSubtree: true))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records label semantics and ignores subtree")
    func recordsLabelSemanticsAndIgnoresSubtree() {
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
            ignoreSubtree: true
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
            ignoreSubtree: true
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
    @Test("Records image semantics and ignores subtree")
    func recordsImageSemanticsAndIgnoresSubtree() {
        // Given
        let image = UIImage()
        let highlightedImage = UIImage()
        let imageView = UIImageView(image: image, highlightedImage: highlightedImage)
        imageView.isHighlighted = true
        imageView.tintColor = .green

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: imageView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .image(
                .init(
                    image: image,
                    highlightedImage: highlightedImage,
                    isHighlighted: true,
                    tintColor: .green
                )
            ),
            ignoreSubtree: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records progress semantics and ignores subtree")
    func recordsProgressSemanticsAndIgnoresSubtree() {
        // Given
        let progressView = UIProgressView()
        progressView.progress = 0.75

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: progressView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .progress(.init(progress: 0.75)), ignoreSubtree: true))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records stepper semantics and ignores subtree")
    func recordsStepperSemanticsAndIgnoresSubtree() {
        // Given
        let stepper = UIStepper()
        stepper.value = 7

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: stepper.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .stepper(.init(value: 7)), ignoreSubtree: true))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records text view semantics and ignores subtree")
    func recordsTextViewSemanticsAndIgnoresSubtree() {
        // Given
        let textView = UITextView()
        textView.text = "Body"
        textView.isEditable = false
        textView.isSecureTextEntry = true

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textView.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .text(
                .init(
                    text: "Body",
                    isEditable: false,
                    isSecureTextEntry: true
                )
            ),
            ignoreSubtree: true
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records text field semantics and keeps subtree")
    func recordsTextFieldSemanticsAndKeepsSubtree() {
        // Given
        let textField = UITextField()
        textField.text = "Value"
        textField.placeholder = "Placeholder"
        textField.isSecureTextEntry = true

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: textField.layer, context: .mockAny())

        // Then
        #expect(observation == .init(
            semantics: .textField(
                .init(
                    text: "Value",
                    placeholder: "Placeholder",
                    isSecureTextEntry: true
                )
            )
        ))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Records switch semantics and ignores subtree")
    func recordsSwitchSemanticsAndIgnoresSubtree() {
        // Given
        let switchControl = UISwitch()
        switchControl.isOn = true

        // When
        let observation = CALayerSnapshot.SemanticObservation(layer: switchControl.layer, context: .mockAny())

        // Then
        #expect(observation == .init(semantics: .switchControl(.init(isOn: true)), ignoreSubtree: true))
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
        #expect(observation == .init(semantics: .webView(.init(slotID: webView.hash)), ignoreSubtree: true))
        #expect(webViewCache.allObjects.first === webView)
    }
}

#endif
