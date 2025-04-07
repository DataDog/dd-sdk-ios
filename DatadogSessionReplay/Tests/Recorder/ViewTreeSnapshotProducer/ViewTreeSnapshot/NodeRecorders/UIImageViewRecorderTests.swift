/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay

// swiftlint:disable opening_brace
class UIImageViewRecorderTests: XCTestCase {
    private let recorder = UIImageViewRecorder(identifier: UUID())
    /// The view under test.
    private let imageView = UIImageView()
    /// `ViewAttributes` simulating common attributes of image view's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    // MARK: Appearance
    func testWhenImageViewHasNoImageAndNoAppearance() throws {
        // When
        imageView.image = nil
        viewAttributes = .mock(fixture: .visible(.noAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)
    }

    func testWhenImageViewHasNoImageAndHasSomeAppearance() throws {
        // When
        imageView.image = nil
        viewAttributes = .mock(fixture: .visible(.someAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .record, "Image view's subtree should be recorded")
        XCTAssertTrue(semantics.nodes.first?.wireframesBuilder is UIImageViewWireframesBuilder)
    }

    func testWhenImageViewHasImageAndSomeAppearance() throws {
        // When
        imageView.image = UIImage()
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .record, "Image view's subtree should be recorded")
        XCTAssertTrue(semantics.nodes.first?.wireframesBuilder is UIImageViewWireframesBuilder)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }

    // MARK: Predicate Override
    func testWhenShouldRecordImagePredicateOverrideReturnsFalse() throws {
        // When
        let recorder = UIImageViewRecorder(identifier: UUID(), shouldRecordImagePredicateOverride: { _ in return false })
        imageView.image = UIImage()
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .record, "Image view's subtree should be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIImageViewWireframesBuilder)
        XCTAssertNil(builder.imageResource)
    }

    func testWhenShouldRecordImagePredicateOverrideReturnsTrue() throws {
        // When
        let recorder = UIImageViewRecorder(identifier: UUID(), shouldRecordImagePredicateOverride: { _ in return true })
        imageView.image = UIImage()
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .record, "Image view's subtree should be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIImageViewWireframesBuilder)
        XCTAssertNotNil(builder.imageResource)
    }

    // MARK: Image Privacy
    func testWhenMaskAllImagePrivacy_itDoesNotRecordImage() throws {
        // Given
        let imagePrivacy = ImagePrivacyLevel.maskAll
        let context = ViewTreeRecordingContext.mockWith(recorder: .mockWith(imagePrivacy: imagePrivacy))

        // When
        let recorder = UIImageViewRecorder(identifier: UUID())
        imageView.image = UIImage()
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: context))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .record, "Image view's subtree should be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIImageViewWireframesBuilder)
        XCTAssertNil(builder.imageResource)
    }

    func testWhenMaskNoneImagePrivacy_itDoesRecordImage() throws {
        // Given
        let imagePrivacy = ImagePrivacyLevel.maskNone
        let context = ViewTreeRecordingContext.mockWith(recorder: .mockWith(imagePrivacy: imagePrivacy))

        // When
        let recorder = UIImageViewRecorder(identifier: UUID())
        imageView.image = UIImage()
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: context))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .record, "Image view's subtree should be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIImageViewWireframesBuilder)
        XCTAssertNotNil(builder.imageResource)
    }

    func testWhenMaskContentImagePrivacy_itDoesRecordSFSymbolImage() throws {
        // Given
        let imagePrivacy = ImagePrivacyLevel.maskNonBundledOnly
        let context = ViewTreeRecordingContext.mockWith(recorder: .mockWith(imagePrivacy: imagePrivacy))

        // When
        let recorder = UIImageViewRecorder(identifier: UUID())
        if #available(iOS 13.0, *) {
            imageView.image = UIImage(systemName: "star")
        }
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: context))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .record, "Image view's subtree should be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIImageViewWireframesBuilder)
        XCTAssertNotNil(builder.imageResource)
    }

    // MARK: Privacy Overrides
    func testWhenImageViewHasImagePrivacyOverride() throws {
        // Given
        let globalImagePrivacy = ImagePrivacyLevel.maskNone
        let context = ViewTreeRecordingContext.mockWith(recorder: .mockWith(imagePrivacy: globalImagePrivacy))

        imageView.image = UIImage()
        let overrideImagePrivacy: ImagePrivacyLevel = .maskAll
        let overrides: PrivacyOverrides = .mockWith(imagePrivacy: overrideImagePrivacy)
        viewAttributes = .mockWith(overrides: overrides)

        // When
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: context))

        // Then
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIImageViewWireframesBuilder)
        XCTAssertNil(builder.imageResource)
    }
}
// swiftlint:enable opening_brace
#endif
