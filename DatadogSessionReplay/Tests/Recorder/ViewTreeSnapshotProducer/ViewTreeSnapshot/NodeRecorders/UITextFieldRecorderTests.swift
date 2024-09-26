/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay

// swiftlint:disable opening_brace
class UITextFieldRecorderTests: XCTestCase {
    private let recorder = UITextFieldRecorder(identifier: UUID())
    /// The label under test.
    private let textField = UITextField(frame: .mockAny())
    /// `ViewAttributes` simulating common attributes of text field's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    private func textObfuscator(in privacyMode: TextAndInputPrivacyLevel) throws -> TextObfuscating {
        try recorder
            .semantics(of: textField, with: viewAttributes, in: .mockWith(recorder: .mockWith(textAndInputPrivacy: privacyMode)))
            .expectWireframeBuilder(ofType: UITextFieldWireframesBuilder.self)
            .textObfuscator
    }

    func testWhenTextFieldIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textField, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
    }

    func testWhenTextFieldHasText() throws {
        // Given
        let randomText: String = .mockRandom()
        textField.textColor = .mockRandom()
        textField.font = .systemFont(ofSize: .mockRandom())

        // When
        oneOf([
            {
                self.textField.text = randomText
                self.textField.placeholder = nil
            },
            {
                self.textField.text = nil
                self.textField.placeholder = randomText
            },
            {
                self.textField.text = randomText
                self.textField.placeholder = .mockRandom()
            },
        ])
        viewAttributes = .mock(fixture: .visible(.someAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textField, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)

        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UITextFieldWireframesBuilder)
        XCTAssertEqual(builder.text, randomText)
        XCTAssertEqual(builder.textColor, textField.textColor?.cgColor)
        XCTAssertEqual(builder.font, textField.font)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UILabel()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }

    func testTextObfuscationOfNoSensitiveText() throws {
        // When
        textField.text = .mockRandom()
        textField.isSecureTextEntry = false // non-sensitive
        textField.textContentType = nil // non-sensitive
        viewAttributes = .mock(fixture: .visible())

        // Then
        XCTAssertTrue(try textObfuscator(in: .maskSensitiveInputs) is NOPTextObfuscator)
        XCTAssertTrue(try textObfuscator(in: .maskAllInputs) is FixLengthMaskObfuscator)
        XCTAssertTrue(try textObfuscator(in: .maskAll) is FixLengthMaskObfuscator)
    }

    func testTextObfuscationOfSensitiveText() throws {
        // When
        textField.text = .mockRandom()
        oneOrMoreOf([
            { self.textField.isSecureTextEntry = true },
            { self.textField.textContentType = UITextField.dd.sensitiveTypes.randomElement() },
        ])

        // Then
        XCTAssertTrue(try textObfuscator(in: .mockRandom()) is FixLengthMaskObfuscator)

        // When
        textField.isSecureTextEntry = false // non-sensitive
        textField.textContentType = nil // non-sensitive

        // Then - it keeps obfuscating
        XCTAssertTrue(try textObfuscator(in: .mockRandom()) is FixLengthMaskObfuscator)
    }
}
// swiftlint:enable opening_brace
#endif
