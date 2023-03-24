/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

// swiftlint:disable opening_brace
class UITextFieldRecorderTests: XCTestCase {
    private let recorder = UITextFieldRecorder()
    /// The label under test.
    private let textField = UITextField(frame: .mockAny())
    /// `ViewAttributes` simulating common attributes of text field's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

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

    func testWhenRecordingInDifferentPrivacyModes() throws {
        // Given
        let textField1 = UITextField(frame: .mockAny())
        let textField2 = UITextField(frame: .mockAny())
        let textField3 = UITextField(frame: .mockAny())
        textField1.text = .mockRandom()
        textField2.text = .mockRandom()
        textField3.text = .mockRandom()

        textField2.isSecureTextEntry = true
        textField3.textContentType = [.telephoneNumber, .emailAddress].randomElement()!

        // When
        viewAttributes = .mock(fixture: .visible())
        let context: ViewTreeRecordingContext = .mockWith(
            recorder: .mockWith(privacy: .mockRandom()),
            textObfuscator: TextObfuscatorMock(),
            selectionTextObfuscator: mockRandomTextObfuscator(),
            sensitiveTextObfuscator: TextObfuscatorMock()
        )

        let semantics1 = try XCTUnwrap(recorder.semantics(of: textField1, with: viewAttributes, in: context))
        let semantics2 = try XCTUnwrap(recorder.semantics(of: textField2, with: viewAttributes, in: context))
        let semantics3 = try XCTUnwrap(recorder.semantics(of: textField3, with: viewAttributes, in: context))

        // Then
        let builder1 = try XCTUnwrap(semantics1.nodes.first?.wireframesBuilder as? UITextFieldWireframesBuilder)
        let builder2 = try XCTUnwrap(semantics2.nodes.first?.wireframesBuilder as? UITextFieldWireframesBuilder)
        let builder3 = try XCTUnwrap(semantics3.nodes.first?.wireframesBuilder as? UITextFieldWireframesBuilder)

        XCTAssertTrue(
            (builder1.textObfuscator as? TextObfuscatorMock) === (context.textObfuscator as? TextObfuscatorMock),
            "Non-sensitive text fields should use default text obfuscator specific to current privacy mode"
        )
        XCTAssertTrue(
            (builder2.textObfuscator as? TextObfuscatorMock) === (context.sensitiveTextObfuscator as? TextObfuscatorMock),
            "Sensitive text fields should use sensitive text obfuscator no matter of privacy mode"
        )
        XCTAssertTrue(
            (builder3.textObfuscator as? TextObfuscatorMock) === (context.sensitiveTextObfuscator as? TextObfuscatorMock),
            "Sensitive text fields should use sensitive text obfuscator no matter of privacy mode"
        )
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UILabel()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
// swiftlint:enable opening_brace
