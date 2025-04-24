/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay
@_spi(Internal)
@testable import TestUtilities

// swiftlint:disable opening_brace
class UILabelRecorderTests: XCTestCase {
    private let recorder = UILabelRecorder(identifier: UUID())
    /// The label under test.
    private let label = UILabel()
    /// `ViewAttributes` simulating common attributes of label's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenLabelHasNoTextAndNoAppearance() throws {
        // When
        oneOf([
            { self.label.text = nil },
            { self.label.text = "" },
        ])
        viewAttributes = .mock(fixture: .visible(.noAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: label, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)
    }

    func testWhenLabelHasTextOrAppearance() throws {
        // When
        oneOf([
            {
                self.label.text = .mockRandom()
                self.viewAttributes = .mock(fixture: .visible())
            },
            {
                self.label.text = nil
                self.viewAttributes = .mock(fixture: .visible())
            },
            {
                self.label.text = .mockRandom()
                self.viewAttributes = .mock(fixture: .visible(.noAppearance))
            },
        ])

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: label, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "Label's subtree should not be recorded")

        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UILabelWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
        XCTAssertEqual(builder.text, label.text ?? "")
        XCTAssertEqual(builder.textColor, label.textColor?.cgColor)
        XCTAssertEqual(builder.font, label.font)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }

    func testTextObfuscationInDifferentPrivacyModes() throws {
        // When
        label.text = .mockRandom()
        viewAttributes = .mock(fixture: .visible())

        // Then
        func textObfuscator(in privacyMode: TextAndInputPrivacyLevel) throws -> TextObfuscating {
            return try recorder
                .semantics(of: label, with: viewAttributes, in: .mockWith(recorder: .mockWith(textAndInputPrivacy: privacyMode)))
                .expectWireframeBuilder(ofType: UILabelWireframesBuilder.self)
                .textObfuscator
        }

        XCTAssertTrue(try textObfuscator(in: .maskSensitiveInputs) is NOPTextObfuscator)
        XCTAssertTrue(try textObfuscator(in: .maskAllInputs) is NOPTextObfuscator)
        XCTAssertTrue(try textObfuscator(in: .maskAll) is SpacePreservingMaskObfuscator)
    }

    func testWhenLabelHasTextPrivacyOverride() throws {
        // Given
        label.text = .mockRandom()
        viewAttributes = .mock(fixture: .visible())
        viewAttributes.textAndInputPrivacy = .maskAll

        // When
        let semantics = try XCTUnwrap(recorder.semantics(of: label, with: viewAttributes, in: .mockAny()) as? SpecificElement)

        // Then
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UILabelWireframesBuilder)
        XCTAssertTrue(builder.textObfuscator is SpacePreservingMaskObfuscator)
    }
}
// swiftlint:enable opening_brace
#endif
