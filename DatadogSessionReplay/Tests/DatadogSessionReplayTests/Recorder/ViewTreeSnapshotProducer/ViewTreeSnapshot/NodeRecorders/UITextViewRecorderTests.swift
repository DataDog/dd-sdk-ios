/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

// swiftlint:disable opening_brace
class UITextViewRecorderTests: XCTestCase {
    private let recorder = UITextViewRecorder()
    /// The label under test.
    private let textView = UITextView()
    /// `ViewAttributes` simulating common attributes of text view's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenTextViewIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertNil(semantics.wireframesBuilder)
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
        viewAttributes = .mock(fixture: .visibleWithSomeAppearance)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textView, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertTrue(semantics.recordSubtree, "TextView's subtree should be recorded")

        let builder = try XCTUnwrap(semantics.wireframesBuilder as? UITextViewWireframesBuilder)
        XCTAssertEqual(builder.text, randomText)
        XCTAssertEqual(builder.textColor, textView.textColor?.cgColor)
        XCTAssertEqual(builder.font, textView.font)
    }

    func testWhenRecordingInDifferentPrivacyModes() throws {
        // Given
        textView.text = .mockRandom()

        // When
        viewAttributes = .mock(fixture: .visibleWithSomeAppearance)
        let semantics1 = try XCTUnwrap(recorder.semantics(of: textView, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: .maskAll))))
        let semantics2 = try XCTUnwrap(recorder.semantics(of: textView, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: .allowAll))))

        // Then
        let builder1 = try XCTUnwrap(semantics1.wireframesBuilder as? UITextViewWireframesBuilder)
        let builder2 = try XCTUnwrap(semantics2.wireframesBuilder as? UITextViewWireframesBuilder)
        XCTAssertTrue(builder1.textObfuscator is TextObfuscator, "With `.maskAll` privacy the text obfuscator should be used")
        XCTAssertTrue(builder2.textObfuscator is NOPTextObfuscator, "With `.allowAll` privacy the text obfuscator should not be used")
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UILabel()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
// swiftlint:enable opening_brace
