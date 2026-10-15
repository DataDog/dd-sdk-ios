// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
// Host-only pixel decoding. This tool grants no native or SDK acceptance.
import Foundation
import AVFoundation
import CoreImage
import ImageIO
import Vision
import CryptoKit

private enum DisplayFailure: Error { case invalid(String) }
private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw DisplayFailure.invalid(message) }
}
private let maximumBytes = 512 * 1024 * 1024
private let maximumDimension = 8_192
private let maximumFrames = 36_000
private func save(_ value: [String: Any], to path: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    try data.write(to: path, options: [.withoutOverwriting])
}
private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
private func dimensions(_ width: Int, _ height: Int) throws {
    try require(width > 0 && height > 0 && width <= maximumDimension && height <= maximumDimension,
                "image dimensions exceed decoder limits")
}
private func finite(_ rect: CGRect) -> Bool {
    [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite }
}

private final class Decoder {
    let destination: URL
    let stream: FileHandle
    let context = CIContext(options: [.useSoftwareRenderer: false])
    let request = VNDetectBarcodesRequest()
    var count = 0
    init(destination: URL) throws {
        self.destination = destination
        let path = destination.appendingPathComponent("frames.jsonl")
        try require(!FileManager.default.fileExists(atPath: path.path), "decoder output already exists")
        try Data().write(to: path, options: [.withoutOverwriting])
        stream = try FileHandle(forWritingTo: path)
        request.symbologies = [.qr]
        request.revision = VNDetectBarcodesRequestRevision3
    }
    deinit { try? stream.close() }
    func frame(_ image: CGImage, pts: CMTime? = nil) throws {
        try dimensions(image.width, image.height)
        try require(count < maximumFrames && !Task.isCancelled, "decoder cancelled or frame limit exceeded")
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let found = request.results ?? []
        try require(found.count <= 8, "too many barcode observations")
        var boxes: [CGRect] = []
        var geometry = true
        let observations: [[String: Any]] = found.map { item in
            let b = item.boundingBox
            let pixels = CGRect(x: b.minX * Double(image.width), y: (1 - b.maxY) * Double(image.height),
                                width: b.width * Double(image.width), height: b.height * Double(image.height))
            // Enclosing integer pixels absorb fractional conversion noise. Raw bounds remain in the receipt.
            let enclosed = finite(pixels) ? pixels.integral : .zero
            let valid = finite(pixels) && pixels.width > 0 && pixels.height > 0
                && pixels.minX >= -1 && pixels.minY >= -1
                && pixels.maxX <= Double(image.width) + 1 && pixels.maxY <= Double(image.height) + 1
            geometry = geometry && valid && boxes.allSatisfy { $0.intersection(enclosed).isNull || $0.intersection(enclosed).isEmpty }
            boxes.append(enclosed)
            return ["payload": item.payloadStringValue as Any? ?? NSNull(), "confidence": item.confidence,
                    "rawNormalizedBounds": [b.minX, b.minY, b.width, b.height],
                    "enclosingPixels": [enclosed.minX, enclosed.minY, enclosed.width, enclosed.height]]
        }
        var value: [String: Any] = ["index": count, "width": image.width, "height": image.height,
                                    "geometryValid": geometry, "observations": observations]
        if let pts { value["pts"] = ["value": pts.value, "timescale": pts.timescale, "epoch": pts.epoch, "flags": pts.flags.rawValue] }
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]); data.append(10)
        try stream.write(contentsOf: data)
        count += 1
    }
    func raster(_ image: CIImage) throws -> CGImage {
        let extent = image.extent.integral
        try require(finite(extent), "nonfinite transformed image")
        try require(extent.width > 0 && extent.height > 0 && extent.width <= Double(maximumDimension)
                    && extent.height <= Double(maximumDimension), "transformed dimensions exceed limits")
        try dimensions(Int(extent.width), Int(extent.height))
        guard let result = context.createCGImage(image, from: extent) else { throw DisplayFailure.invalid("pixel rendering failed") }
        return result
    }
    func image(_ input: URL) throws -> [String: Any] {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw DisplayFailure.invalid("invalid image") }
        try dimensions(width, height)
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw DisplayFailure.invalid("image decoding failed") }
        let orientation = properties[kCGImagePropertyOrientation] as? Int32 ?? 1
        try require((1...8).contains(orientation), "unknown image orientation")
        try frame(raster(CIImage(cgImage: image).oriented(forExifOrientation: orientation)))
        return ["kind": "IMAGE", "imageOrientation": orientation, "rawSize": [width, height], "readerState": "completed"]
    }
    func movie(_ input: URL) async throws -> [String: Any] {
        let asset = AVURLAsset(url: input)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        try require(tracks.count == 1, "expected one selected video track")
        let track = tracks[0]
        let transform = try await track.load(.preferredTransform)
        let size = try await track.load(.naturalSize)
        try require(size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
                    && size.width <= Double(maximumDimension) && size.height <= Double(maximumDimension), "invalid track geometry")
        let coefficients = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
        try require(coefficients.allSatisfy { $0.isFinite && abs($0) <= Double(maximumDimension * 2) }, "invalid track transform")
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        try require(reader.canAdd(output), "video output unavailable"); reader.add(output)
        try require(reader.startReading(), "video reader did not start")
        var previous: CMTime?
        do {
            while let sample = output.copyNextSampleBuffer() {
                try require(CMSampleBufferDataIsReady(sample) && CMSampleBufferGetNumSamples(sample) == 1, "invalid video sample")
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                try require(pts.isValid && pts.isNumeric && pts.timescale > 0, "invalid video presentation time")
                if let previous { try require(pts.epoch == previous.epoch && CMTimeCompare(pts, previous) >= 0, "regressing presentation time") }
                guard let pixels = CMSampleBufferGetImageBuffer(sample) else { throw DisplayFailure.invalid("missing decoded pixels") }
                try dimensions(CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels))
                try autoreleasepool { try frame(raster(CIImage(cvPixelBuffer: pixels).transformed(by: transform)), pts: pts) }
                previous = pts
            }
            try require(reader.status == .completed && reader.error == nil && count > 0, "video read failed, cancelled or incomplete")
        } catch { reader.cancelReading(); throw error }
        return ["kind": "MOVIE", "readerState": "completed", "trackCount": tracks.count, "trackID": track.trackID,
                "naturalSize": [size.width, size.height], "preferredTransform": coefficients,
                "pixelFormat": kCVPixelFormatType_32BGRA, "decodedOutput": true]
    }
}

// Synthetic media belongs to offline codec controls, never to native evidence.
private func fixtureImage(_ value: [String: Any]) throws -> CGImage {
    guard let payloads = value["payloads"] as? [String], payloads.count <= 4 else {
        throw DisplayFailure.invalid("invalid fixture specification")
    }
    let scale = value["scale"] as? Int ?? 1
    try require((1...3).contains(scale), "invalid fixture scale")
    let width = 640 * scale, height = 640 * scale
    guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw DisplayFailure.invalid("fixture canvas")
    }
    canvas.setFillColor(CGColor(gray: 1, alpha: 1)); canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
    canvas.interpolationQuality = .none
    let context = CIContext()
    for (index, payload) in payloads.enumerated() {
        try require(payload.utf8.count <= 512, "fixture payload too large")
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw DisplayFailure.invalid("QR generator unavailable") }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage"); filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage, let qr = context.createCGImage(image, from: image.extent) else {
            throw DisplayFailure.invalid("QR generation failed")
        }
        let moduleScale = max(1, Int(Double(260 * scale) / image.extent.width)); let side = qr.width * moduleScale
        canvas.draw(qr, in: CGRect(x: (index % 2 * 320 + 30) * scale,
                                  y: (index / 2 * 320 + 30) * scale, width: side, height: side))
    }
    guard let image = canvas.makeImage() else { throw DisplayFailure.invalid("fixture raster") }
    return image
}

private func fixture(_ value: [String: Any], _ output: URL) throws {
    let image = try fixtureImage(value)
    let orientation = value["orientation"] as? Int ?? 1
    try require((1...8).contains(orientation), "invalid fixture orientation")
    let format = value["format"] as? String ?? "png"
    try require(["png", "jpeg"].contains(format), "invalid fixture format")
    guard let target = CGImageDestinationCreateWithURL(output as CFURL,
        (format == "png" ? "public.png" : "public.jpeg") as CFString, 1, nil) else {
        throw DisplayFailure.invalid("fixture output")
    }
    let properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation,
                                       kCGImageDestinationLossyCompressionQuality: 0.75]
    CGImageDestinationAddImage(target, image, properties as CFDictionary)
    try require(CGImageDestinationFinalize(target), "fixture image finalization failed")
}

private func fixtureMovie(_ value: [String: Any], _ output: URL) async throws {
    guard let frames = value["frames"] as? [[String: Any]], !frames.isEmpty, frames.count <= 120 else {
        throw DisplayFailure.invalid("invalid fixture frames")
    }
    let rotation = value["rotation"] as? Int ?? 0
    try require([0, 90, 180, 270].contains(rotation), "invalid fixture rotation")
    let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 640,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000]])
    input.transform = CGAffineTransform(rotationAngle: Double(rotation) * .pi / 180)
    let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                     kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 640]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
    try require(writer.canAdd(input), "fixture movie input unavailable"); writer.add(input)
    try require(writer.startWriting(), "fixture writer did not start"); writer.startSession(atSourceTime: .zero)
    let context = CIContext()
    do {
        for (index, spec) in frames.enumerated() {
            let image = try fixtureImage(spec)
            try require(image.width == 640 && image.height == 640, "fixture movie dimensions differ")
            let deadline = Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData {
                try require(writer.status == .writing && Date() < deadline && !Task.isCancelled, "fixture writer stalled")
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw DisplayFailure.invalid("fixture pixel pool") }
            var buffer: CVPixelBuffer?
            try require(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, "fixture pixel allocation")
            guard let buffer else { throw DisplayFailure.invalid("fixture pixels missing") }
            context.render(CIImage(cgImage: image), to: buffer)
            try require(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 6)),
                        "fixture sample append failed")
        }
        input.markAsFinished(); await writer.finishWriting()
        try require(writer.status == .completed && writer.error == nil, "fixture movie did not finalize")
    } catch { writer.cancelWriting(); throw error }
}

@main struct OperationDisplay {
    static func main() async {
        var status = 0
        do {
            let args = CommandLine.arguments
            try require(args.count == 4, "usage: operation-display image|movie|fixture|fixture-movie INPUT OUTPUT")
            let input = URL(fileURLWithPath: args[2]), output = URL(fileURLWithPath: args[3])
            let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
            try require(attributes[.type] as? FileAttributeType == .typeRegular && size > 0 && size <= maximumBytes, "invalid or oversized input")
            if ["fixture", "fixture-movie"].contains(args[1]) {
                try require(size <= 1024 * 1024 && !FileManager.default.fileExists(atPath: output.path), "invalid or consumed fixture")
                guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as? [String: Any] else {
                    throw DisplayFailure.invalid("invalid fixture specification")
                }
                if args[1] == "fixture" { try fixture(value, output) }
                else { try await fixtureMovie(value, output) }
                return
            }
            try require(args[1] == "image" || args[1] == "movie", "unknown decode kind")
            try require(!FileManager.default.fileExists(atPath: output.path), "decoder output consumed")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            let decoder = try Decoder(destination: output)
            do {
                var result: [String: Any]
                if args[1] == "movie" { result = try await decoder.movie(input) }
                else { result = try decoder.image(input) }
                try decoder.stream.synchronize()
                result.merge(["schemaVersion": 1, "state": "DECODED", "inputSHA256": digest(try Data(contentsOf: input, options: .mappedIfSafe)),
                    "framesSHA256": digest(try Data(contentsOf: output.appendingPathComponent("frames.jsonl"))), "frameCount": decoder.count,
                    "revision": VNDetectBarcodesRequestRevision3, "limits": ["bytes": maximumBytes, "dimension": maximumDimension, "frames": maximumFrames],
                    "nativeAcceptance": false]) { _, new in new }
                try save(result, to: output.appendingPathComponent("decoder.json"))
            } catch {
                try? save(["schemaVersion": 1, "state": "DECODER_FAILED", "frameCount": decoder.count,
                           "nativeAcceptance": false, "error": String(describing: error)], to: output.appendingPathComponent("decoder.json"))
                throw error
            }
        } catch { FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8)); status = 1 }
        if status != 0 { exit(Int32(status)) }
    }
}
