/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class UITextFieldRecorderTests: XCTestCase {
    private let recorder = UITextFieldRecorder()
    /// The label under test.
    private let textField = UITextField(frame: .mockAny())
    /// `ViewAttributes` simulating common attributes of text field's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenTextFieldIsNotVisible() throws {
        // When
        viewAttributes = .mockWith(isVisible: false)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textField, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertNil(semantics.wireframesBuilder)
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
        viewAttributes = .mockWith(isVisible: true)
        textField.layoutSubviews() // force layout (so TF creates its sub-tree)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textField, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)

        let builder = try XCTUnwrap(semantics.wireframesBuilder as? UITextFieldWireframesBuilder)
        XCTAssertEqual(builder.text, randomText)
        XCTAssertEqual(builder.textColor, textField.textColor?.cgColor)
        XCTAssertEqual(builder.font, textField.font)
        XCTAssertNotNil(builder.editor)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UILabel()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
