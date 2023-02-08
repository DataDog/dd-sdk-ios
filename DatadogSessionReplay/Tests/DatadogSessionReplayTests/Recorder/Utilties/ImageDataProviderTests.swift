/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class ImageDataProviderTests: XCTestCase {
    func test_returnsEmptyString_WhenContentIsEmpty() {
        let sut = ImageDataProvider(
            queue: NoQueue()
        )

        let imageString = sut.contentBase64String(of: UIImageView())

        XCTAssertEqual(imageString, "")
    }

    func test_returnsValidString_WhenContentIsValid() throws {
        let sut = ImageDataProvider(
            queue: NoQueue()
        )
        let base64 = "R0lGODlhAQABAIAAAP7//wAAACH5BAAAAAAALAAAAAABAAEAAAICRAEAOw=="
        let image = UIImage(data: Data(base64Encoded: base64)!)

        XCTAssertNil(sut.contentBase64String(of: UIImageView(image: image)))
        let imageData = try XCTUnwrap(sut.contentBase64String(of: UIImageView(image: image)))
        XCTAssertGreaterThan(imageData.count, 0)
    }

    @available(iOS 13.0, *)
    func test_returnsValidString_forSFSymbolIcon() throws {
        let sut = ImageDataProvider(
            queue: NoQueue()
        )

        let image = UIImage(systemName: "apple.logo")

        XCTAssertNil(sut.contentBase64String(of: UIImageView(image: image)))
        let imageData = try XCTUnwrap(sut.contentBase64String(of: UIImageView(image: image)))
        XCTAssertGreaterThan(imageData.count, 0)
    }

    func test_returnsValidString_forAssetImage() throws {
        let sut = ImageDataProvider(
            queue: NoQueue()
        )

        let image = UIImage(named: "dd_logo_v_rgb", in: Bundle.module, compatibleWith: nil)

        XCTAssertNil(sut.contentBase64String(of: UIImageView(image: image)))
        let imageData = try XCTUnwrap(sut.contentBase64String(of: UIImageView(image: image)))
        XCTAssertGreaterThan(imageData.count, 0)
    }

    func test_utilisesCorrectCacheKey_whenImagesAreSwizzled() throws {
        UIImage.swizzleInitializersIfNeeded()
        let cache = Cache<String, ImageDataProvider.DataLoadingStatus>()
        let sut = ImageDataProvider(
            cache: cache,
            queue: NoQueue()
        )

        let image = UIImage(named: "dd_logo_v_rgb", in: Bundle.module, compatibleWith: nil)

        XCTAssertNil(sut.contentBase64String(of: UIImageView(image: image)))
        let imageData = try XCTUnwrap(sut.contentBase64String(of: UIImageView(image: image)))
        if case let .loaded(cachedData) = cache["dd_logo_v_rgb#007AFFFF"] {
            XCTAssertEqual(imageData, cachedData)
        } else {
            XCTFail("Cache doesn't exist")
        }
    }
}

#if XCODE_BUILD
extension Foundation.Bundle {
    /// Returns resource bundle as a `Bundle`.
    /// Requires Xcode copy phase to locate files into `ExecutableName.bundle`;
    /// or `ExecutableNameTests.bundle` for test resources
    static var module: Bundle = {
        var thisModuleName = "DatadogSessionReplay"
        var url = Bundle.main.bundleURL

        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            url = bundle.bundleURL.deletingLastPathComponent()
            thisModuleName = thisModuleName.appending("Tests")
        }

        url = url.appendingPathComponent("\(thisModuleName).bundle")

        guard let bundle = Bundle(url: url) else {
            fatalError("Foundation.Bundle.module could not load resource bundle: \(url.path)")
        }

        return bundle
    }()
}
#endif
