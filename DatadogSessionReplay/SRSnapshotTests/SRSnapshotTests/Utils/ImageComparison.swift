/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import XCTest

internal struct ReferenceImage {
    let url: URL

    private init(path: String, file: StaticString = #filePath) {
        self.url = URL(fileURLWithPath: "\(file)", isDirectory: false)
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    /// Creates reference image in folder with given name.
    /// The folder will be placed next to current file.
    /// The image will be named by the name of current test and suffixed with `imageFileSuffix`.
    static func inFolder(
        named folderName: String,
        imageFileSuffix: String = "",
        file: StaticString = #filePath,
        function: StaticString = #function
    ) -> ReferenceImage {
        return ReferenceImage(path: "\(folderName)/\(function)\(imageFileSuffix).png", file: file)
    }
}

/// Compares image against reference file OR updates reference file with image data (if `record == true`).
///
/// It raises `XCTest` assertion failure if image is different than reference.
///
/// - Parameters:
///   - image: the image to compare OR record
///   - referenceImage: the reference file to compare against
///   - record: if `true`, then reference file will be created / overwritten with `image` data
///   - file: `#filePath` for eventual `XCTest` assertion failure
///   - line: `#line` for eventual `XCTest` assertion failure
internal func compare(
    image: UIImage,
    referenceImage: ReferenceImage,
    record: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
    let osVersion = UIDevice.current.systemVersion

    guard simulatorModel == "iPhone14,7", osVersion == "16.2" else {
        XCTFail(
            "Snapshots must be compared on iPhone 14 Simulator (iPhone14,7) + iOS 16.2. " +
            "Running on \(simulatorModel ?? "unknown") + iOS \(osVersion) instead.",
            file: file,
            line: line
        )
        return
    }

    if record {
        let directoryURL = referenceImage.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try XCTUnwrap(image.pngData(), "Failed to create `pngData()` for `image`", file: file, line: line)
        try data.write(to: referenceImage.url)
    } else {
        let oldImageData = try Data(contentsOf: referenceImage.url)
        let oldImage = try XCTUnwrap(UIImage(data: oldImageData), "Failed to read reference image", file: file, line: line)

        // Check if both images are identical (precission: 1) or their difference is not
        // noticable for the human eye (perceptualPrecision: 0.98).
        // Ref.: http://zschuessler.github.io/DeltaE/learn/#toc-defining-delta-e
        if let difference = compare(oldImage, image, precision: 1, perceptualPrecision: 0.98) {
            XCTFail("\(difference) (in file: \(referenceImage.url)", file: file, line: line)
        }
    }
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

func compare(_ old: UIImage, _ new: UIImage, precision: Float, perceptualPrecision: Float) -> String? {
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
