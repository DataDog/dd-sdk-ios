/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

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
        XCTAssertEqual(semantics.subtreeStrategy, .record)

        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UITextViewWireframesBuilder)
        XCTAssertEqual(builder.text, randomText)
        XCTAssertEqual(builder.textColor, textView.textColor?.cgColor)
        XCTAssertEqual(builder.font, textView.font)
    }

    func testWhenRecordingInDifferentPrivacyModes() throws {
        // Given
        textView.text = .mockRandom()

        // When
        viewAttributes = .mock(fixture: .visible())
        let context: ViewTreeRecordingContext = .mockWith(
            recorder: .mockWith(privacy: .mockRandom()),
            textObfuscator: TextObfuscatorMock(),
            selectionTextObfuscator: mockRandomTextObfuscator(),
            sensitiveTextObfuscator: mockRandomTextObfuscator()
        )
        let semantics = try XCTUnwrap(recorder.semantics(of: textView, with: viewAttributes, in: context))

        // Then
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UITextViewWireframesBuilder)
        XCTAssertTrue(
          (builder.textObfuscator as? TextObfuscatorMock) === (context.textObfuscator as? TextObfuscatorMock),
          "Text views should use default text obfuscator specific to current privacy mode"
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
