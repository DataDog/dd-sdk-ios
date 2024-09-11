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

    func testTextObfuscationInDifferentPrivacyModes() throws {
        // When
        textField.text = .mockRandom()
        viewAttributes = .mock(fixture: .visible())

        // Then
        func textObfuscator(in privacyMode: PrivacyLevel) throws -> TextObfuscating {
            return try recorder
                .semantics(of: textField, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: privacyMode)))
                .expectWireframeBuilder(ofType: UITextFieldWireframesBuilder.self)
                .textObfuscator
        }

        XCTAssertTrue(try textObfuscator(in: .allow) is NOPTextObfuscator)
        XCTAssertTrue(try textObfuscator(in: .mask) is FixLengthMaskObfuscator)
        XCTAssertTrue(try textObfuscator(in: .maskUserInput) is FixLengthMaskObfuscator)

        // When
        oneOrMoreOf([
            { self.textField.isSecureTextEntry = true },
            { self.textField.textContentType = sensitiveContentTypes.randomElement() },
        ])

        // Then
        XCTAssertTrue(try textObfuscator(in: .mockRandom()) is FixLengthMaskObfuscator)

        // When
        textField.text = nil
        textField.placeholder = .mockRandom()

        // Then
        XCTAssertTrue(try textObfuscator(in: .allow) is NOPTextObfuscator)
        XCTAssertTrue(try textObfuscator(in: .mask) is FixLengthMaskObfuscator)
        XCTAssertTrue(try textObfuscator(in: .maskUserInput) is NOPTextObfuscator)
    }
}
// swiftlint:enable opening_brace
#endif
