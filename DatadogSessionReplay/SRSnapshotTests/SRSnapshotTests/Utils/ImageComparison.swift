/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import XCTest
import TestUtilities

internal struct ImageLocation {
    let url: URL

    private init(path: String, file: StaticString = #filePath) {
        self.url = URL(fileURLWithPath: "\(file)", isDirectory: false)
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    /// Creates reference image in folder with given name.
    /// The folder will be placed next to current file.
    /// The image will be named by the name of current test and suffixed with `imageFileSuffix`.
    static func folder(
        named folderName: String,
        fileNameSuffix: String = "",
        file: StaticString = #filePath,
        function: StaticString = #function
    ) -> ImageLocation {
        return ImageLocation(path: "\(folderName)/\(function)\(fileNameSuffix).png", file: file)
    }
}

/// Compares `newImage` against the snapshot saved in `snapshotLocation` OR updates stored snapshot image data (if `record == true`).
internal func DDAssertSnapshotTest(
    newImage: UIImage,
    snapshotLocation: ImageLocation,
    record: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    DDAssertSimulatorDevice("iPhone14,7", "16.2", file: file, line: line)

    if record {
        DDSaveSnapshotIfDifferent(image: newImage, into: snapshotLocation, file: file, line: line)
        XCTFail(
            "✅ All OK, we fail tests deliberately to prevent accidentally leaving recording mode enabled",
            file: file,
            line: line
        )
    } else {
        DDAssertSnapshotEquals(snapshotLocation: snapshotLocation, image: newImage, file: file, line: line)
    }
}

/// Asserts that tests are executed on given iOS Simulator.
private func DDAssertSimulatorDevice(_ expectedModel: String, _ expectedOSVersion: String, file: StaticString = #filePath, line: UInt = #line) {
    _DDEvaluateAssertion(message: "Snapshots must be compared on \(expectedModel) Simulator with iOS \(expectedModel)", file: file, line: line) {
        guard let actualModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] else {
            throw DDAssertError.expectedFailure("Not running in Simulator")
        }
        guard actualModel == expectedModel else {
            throw DDAssertError.expectedFailure("Running in \(actualModel) Simulator")
        }
        let actualOSVersion = UIDevice.current.systemVersion
        guard actualOSVersion == expectedOSVersion else {
            throw DDAssertError.expectedFailure("Running on iOS \(actualOSVersion)")
        }
    }
}

/// Writes image PNG data into given location when:
/// - image at `location` doesn't exist;
/// - the difference between `image` and the image at `location` is higher than threshold.
private func DDSaveSnapshotIfDifferent(image: UIImage, into location: ImageLocation, file: StaticString = #filePath, line: UInt = #line) {
    _DDEvaluateAssertion(message: "Failed to write recorded image into \(location.url)", file: file, line: line) {
        let oldFileExists = FileManager.default.fileExists(atPath: location.url.path)
        guard try !oldFileExists || difference(for: image, againstReference: location) != nil else {
            print("🎬 ⏩ Skips saving `\(location.url.lastPathComponent)` as it has no significant difference with existing file")
            return
        }

        print("🎬 📸 Saving `\(location.url.lastPathComponent)`")
        guard let data = image.pngData() else {
            throw DDAssertError.expectedFailure("Failed to create PNG data for `image`")
        }
        let directoryURL = location.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: location.url)
    }
}

/// Compares image against the snapshot saved in given location.
private func DDAssertSnapshotEquals(snapshotLocation: ImageLocation, image: UIImage, file: StaticString = #filePath, line: UInt = #line) {
    let imageName = snapshotLocation.url.lastPathComponent
    _DDEvaluateAssertion(message: "Image '\(imageName)' is visibly different than snapshot", file: file, line: line) {
        if let differenceExplained = try difference(for: image, againstReference: snapshotLocation) {
            throw DDAssertError.expectedFailure(differenceExplained)
        }
    }
}

/// Returns the difference from `image` to the reference image stored at certain `snapshotLocation`.
/// - it returns `nil` if no difference is found (considering the threshold);
/// - it returns human readable string denoting the difference if some is found;
private func difference(for image: UIImage, againstReference snapshotLocation: ImageLocation) throws -> String? {
    let imageName = snapshotLocation.url.lastPathComponent
    let oldImageData = try Data(contentsOf: snapshotLocation.url)
    guard let oldImage = UIImage(data: oldImageData, scale: image.scale) else {
        throw DDAssertError.expectedFailure("Failed to create `UIImage()` from '\(imageName)' snapshot data")
    }

    // Extract "Actual UI" and "Wireframes" images from new and reference snapshots:
    let newImages = extractSideBySideImages(image: image)
    let oldImages = extractSideBySideImages(image: oldImage)

    // Check if both wireframe images are identical (precission: 1) or their difference is not
    // noticable for the human eye (perceptualPrecision: 0.98).
    // Ref.: http://zschuessler.github.io/DeltaE/learn/#toc-defining-delta-e
    return compare(oldImages.wireframes, newImages.wireframes, precision: 1, perceptualPrecision: 0.98)
}

// Copyright © pointfreeco swift-snapshot-testing (MIT License)
// See license: https://github.com/pointfreeco/swift-snapshot-testing/blob/main/LICENSE
//
// This code was taken from https://github.com/pointfreeco/swift-snapshot-testing and
// modified for the purpose of testing Framer lib (© ncreated 2022).
//
// Modifications made:
// - simplification of platform & version specific code branches
import UIKit
import CoreImage.CIKernel
import MetalPerformanceShaders

// MARK: - From `swift-snapshot-testing` /Sources/SnapshotTesting/Snapshotting/UIImage.swift

// remap snapshot & reference to same colorspace
private let imageContextColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
private let imageContextBitsPerComponent = 8
private let imageContextBytesPerPixel = 4

internal func compare(_ old: UIImage, _ new: UIImage, precision: Float, perceptualPrecision: Float) -> String? {
    guard let oldCgImage = old.cgImage else {
        return "Reference image could not be loaded."
    }
    guard let newCgImage = new.cgImage else {
        return "Newly-taken snapshot could not be loaded."
    }
    guard newCgImage.width != 0, newCgImage.height != 0 else {
        return "Newly-taken snapshot is empty."
    }
    guard oldCgImage.width == newCgImage.width, oldCgImage.height == newCgImage.height else {
        return "Newly-taken snapshot@\(new.size) does not match reference@\(old.size)."
    }
    let pixelCount = oldCgImage.width * oldCgImage.height
    let byteCount = imageContextBytesPerPixel * pixelCount
    var oldBytes = [UInt8](repeating: 0, count: byteCount)
    guard let oldData = context(for: oldCgImage, data: &oldBytes)?.data else {
        return "Reference image's data could not be loaded."
    }
    if let newContext = context(for: newCgImage), let newData = newContext.data {
        if memcmp(oldData, newData, byteCount) == 0 { return nil }
    }
    var newerBytes = [UInt8](repeating: 0, count: byteCount)
    guard
        let pngData = new.pngData(),
        let newerCgImage = UIImage(data: pngData)?.cgImage,
        let newerContext = context(for: newerCgImage, data: &newerBytes),
        let newerData = newerContext.data
    else {
        return "Newly-taken snapshot's data could not be loaded."
    }
    if memcmp(oldData, newerData, byteCount) == 0 { return nil }
    if precision >= 1, perceptualPrecision >= 1 {
        return "Newly-taken snapshot does not match reference."
    }
    if perceptualPrecision < 1 {
        return perceptuallyCompare(
            CIImage(cgImage: oldCgImage),
            CIImage(cgImage: newCgImage),
            pixelPrecision: precision,
            perceptualPrecision: perceptualPrecision
        )
    } else {
        let byteCountThreshold = Int((1 - precision) * Float(byteCount))
        var differentByteCount = 0
        for offset in 0..<byteCount {
            if oldBytes[offset] != newerBytes[offset] {
                differentByteCount += 1
            }
        }
        if differentByteCount > byteCountThreshold {
            let actualPrecision = 1 - Float(differentByteCount) / Float(byteCount)
            return "Actual image precision \(actualPrecision) is less than required \(precision)"
        }
    }
    return nil
}

private func context(for cgImage: CGImage, data: UnsafeMutableRawPointer? = nil) -> CGContext? {
    let bytesPerRow = cgImage.width * imageContextBytesPerPixel
    guard
        let colorSpace = imageContextColorSpace,
        let context = CGContext(
            data: data,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: imageContextBitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    return context
}

func perceptuallyCompare(_ old: CIImage, _ new: CIImage, pixelPrecision: Float, perceptualPrecision: Float) -> String? {
    let deltaOutputImage = old.applyingFilter("CILabDeltaE", parameters: ["inputImage2": new])
    let thresholdOutputImage: CIImage
    do {
        thresholdOutputImage = try ThresholdImageProcessorKernel.apply(
            withExtent: new.extent,
            inputs: [deltaOutputImage],
            arguments: [ThresholdImageProcessorKernel.inputThresholdKey: (1 - perceptualPrecision) * 100]
        )
    } catch {
        return "Newly-taken snapshot's data could not be loaded. \(error)"
    }
    var averagePixel: Float = 0
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    context.render(
        thresholdOutputImage.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: new.extent]),
        toBitmap: &averagePixel,
        rowBytes: MemoryLayout<Float>.size,
        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        format: .Rf,
        colorSpace: nil
    )
    let actualPixelPrecision = 1 - averagePixel
    guard actualPixelPrecision < pixelPrecision else { return nil }
    var maximumDeltaE: Float = 0
    context.render(
        deltaOutputImage.applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: new.extent]),
        toBitmap: &maximumDeltaE,
        rowBytes: MemoryLayout<Float>.size,
        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        format: .Rf,
        colorSpace: nil
    )
    let actualPerceptualPrecision = 1 - maximumDeltaE / 100
    if pixelPrecision < 1 {
        return """
    Actual image precision \(actualPixelPrecision) is less than required \(pixelPrecision)
    Actual perceptual precision \(actualPerceptualPrecision) is less than required \(perceptualPrecision)
    """
    } else {
        return "Actual perceptual precision \(actualPerceptualPrecision) is less than required \(perceptualPrecision)"
    }
}

// Copied from https://developer.apple.com/documentation/coreimage/ciimageprocessorkernel
final class ThresholdImageProcessorKernel: CIImageProcessorKernel {
    static let inputThresholdKey = "thresholdValue"
    static let device = MTLCreateSystemDefaultDevice()

    override class func process(with inputs: [CIImageProcessorInput]?, arguments: [String: Any]?, output: CIImageProcessorOutput) throws {
        guard
            let device = device,
            let commandBuffer = output.metalCommandBuffer,
            let input = inputs?.first,
            let sourceTexture = input.metalTexture,
            let destinationTexture = output.metalTexture,
            let thresholdValue = arguments?[inputThresholdKey] as? Float else {
            return
        }

        let threshold = MPSImageThresholdBinary(
            device: device,
            thresholdValue: thresholdValue,
            maximumValue: 1.0,
            linearGrayColorTransform: nil
        )

        threshold.encode(
            commandBuffer: commandBuffer,
            sourceTexture: sourceTexture,
            destinationTexture: destinationTexture
        )
    }
}
