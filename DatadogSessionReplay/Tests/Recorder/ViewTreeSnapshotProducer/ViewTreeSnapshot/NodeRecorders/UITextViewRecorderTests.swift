/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

// swiftlint:disable opening_brace
class UITextViewRecorderTests: XCTestCase {
    private let recorder = UITextViewRecorder(identifier: UUID())
    /// The label under test.
    private let textView = UITextView()
    /// `ViewAttributes` simulating common attributes of text view's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    private func textObfuscator(in privacyMode: TextAndInputPrivacyLevel) throws -> TextObfuscating {
        try recorder
            .semantics(of: textView, with: viewAttributes, in: .mockWith(recorder: .mockWith(textAndInputPrivacy: privacyMode)))
            .expectWireframeBuilder(ofType: UITextViewWireframesBuilder.self)
            .textObfuscator
    }

    func testWhenTextViewIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
    }

    func testWhenTextViewHasText() throws {
        // Given
        let randomText: String = .mockRandom()
        textView.textColor = .mockRandom()
        textView.font = .systemFont(ofSize: .mockRandom())
        // RUMM-2681 Following is required to avoid "CALayer position contains NaN: [0 nan]. (...) (CALayerInvalidGeometry)" error
        textView.layoutManager.allowsNonContiguousLayout = true

        // When
        textView.text = randomText
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)

        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UITextViewWireframesBuilder)
        XCTAssertEqual(builder.text, randomText)
        XCTAssertEqual(builder.textColor, textView.textColor?.cgColor)
        XCTAssertEqual(builder.font, textView.font)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UILabel()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }

    func testTextObfuscationOfNoSensitiveText() throws {
        // When
        textView.text = .mockRandom()
        textView.isSecureTextEntry = false // non-sensitive
        textView.textContentType = nil // non-sensitive
        viewAttributes = .mock(fixture: .visible())

        // Then
        XCTAssertTrue(try textObfuscator(in: .maskSensitiveInputs) is NOPTextObfuscator)
        XCTAssertTrue(try textObfuscator(in: .maskAllInputs) is FixLengthMaskObfuscator)
        XCTAssertTrue(try textObfuscator(in: .maskAll) is FixLengthMaskObfuscator)
    }

    func testTextObfuscationOfSensitiveText() throws {
        // When
        textView.text = .mockRandom()
        textView.isEditable = .mockRandom()
        oneOrMoreOf([
            { self.textView.isSecureTextEntry = true },
            { self.textView.textContentType = UITextView.dd.sensitiveTypes.randomElement() },
        ])

        // Then
        XCTAssertTrue(try textObfuscator(in: .mockRandom()) is FixLengthMaskObfuscator)

        // When
        textView.isEditable = false
        textView.isSecureTextEntry = false // non-sensitive
        textView.textContentType = nil // non-sensitive

        // Then - it keeps obfuscating
        XCTAssertTrue(try textObfuscator(in: .mockRandom()) is FixLengthMaskObfuscator)
    }

    func testWhenTextViewHasTextPrivacyOverride() throws {
        // Given
        textView.text = .mockRandom()
        textView.isEditable = false
        viewAttributes = .mock(fixture: .visible())
        viewAttributes.overrides = .mockWith(textAndInputPrivacy: .maskAll)

        // When
        let semantics = try XCTUnwrap(recorder.semantics(of: textView, with: viewAttributes, in: .mockAny()) as? SpecificElement)

        // Then
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UITextViewWireframesBuilder)
        XCTAssertTrue(builder.textObfuscator is SpacePreservingMaskObfuscator)
    }
}
// swiftlint:enable opening_brace
#endif
