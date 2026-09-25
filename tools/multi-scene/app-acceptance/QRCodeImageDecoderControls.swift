// Copyright © Datadog, Inc. All rights reserved.

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct QRCodeImageDecoderControls {
    static let message = "https://app.datadoghq.com/?dd_referrer=nonce_qrcode&nonce=synthetic-test"

    static func screenshot(messages: [String], rotation: Bool = false, scale: CGFloat = 1) throws -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        var image = CIImage(color: CIColor.white).cropped(to: bounds)
        for (index, message) in messages.enumerated() {
            guard let filter = CIFilter(name: "CIQRCodeGenerator", parameters: [
                "inputMessage": Data(message.utf8), "inputCorrectionLevel": "M",
            ]), let code = filter.outputImage else { throw Failure.fixture }
            let placed = code.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
                .transformed(by: CGAffineTransform(translationX: CGFloat(80 + index * 560), y: 160))
            image = placed.composited(over: image)
        }
        if rotation { image = image.oriented(.right) }
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { throw Failure.fixture }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.fixture
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.fixture }
        return data as Data
    }

    enum Failure: Error { case fixture, assertion }

    static func expectRejected(_ data: Data) throws {
        do {
            _ = try QRCodeImageDecoder.message(in: data)
        } catch is QRCodeImageDecoder.Failure {
            return
        }
        throw Failure.assertion
    }

    static func main() async throws {
        for (rotation, scale) in [(false, CGFloat(1)), (true, 1), (false, 4)] {
            guard try QRCodeImageDecoder.message(in: screenshot(messages: [message], rotation: rotation, scale: scale)) == message else {
                throw Failure.assertion
            }
        }
        try expectRejected(screenshot(messages: []))
        try expectRejected(Data("not an image".utf8))
        try expectRejected(screenshot(messages: [message, "https://example.com/another-code"]))
        try expectRejected(Data(repeating: 0, count: 25 * 1024 * 1024 + 1))
        let cancelled = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try QRCodeImageDecoder.message(in: Data())
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            throw Failure.assertion
        } catch is CancellationError {}
        print("PASS: 8 QR image controls; synthetic data only")
    }
}
