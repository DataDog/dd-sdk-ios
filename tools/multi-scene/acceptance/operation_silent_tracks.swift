// Copyright 2026-Present Datadog, Inc. Licensed under Apache License 2.0.
// Host-only metadata inspection. This utility never captures or plays media.
import AVFoundation
import CryptoKit
import Foundation

private enum InspectionError: Error { case invalid(String) }
private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw InspectionError.invalid(message) }
}
private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@main struct SilentTracks {
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            try require(arguments.count == 3, "usage: silent-tracks INPUT OUTPUT")
            let input = URL(fileURLWithPath: arguments[1])
            let output = URL(fileURLWithPath: arguments[2])
            let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
            try require(attributes[.type] as? FileAttributeType == .typeRegular
                        && size > 0 && size <= 512 * 1024 * 1024, "invalid media file")
            try require(!FileManager.default.fileExists(atPath: output.path), "output already consumed")
            let original = digest(try Data(contentsOf: input, options: .mappedIfSafe))
            let asset = AVURLAsset(url: input)
            let tracks = try await asset.load(.tracks)
            let inventory = tracks.map { ["id": $0.trackID, "mediaType": $0.mediaType.rawValue] as [String: Any] }
            let videos = tracks.filter { $0.mediaType == .video }
            let audios = tracks.filter { $0.mediaType == .audio }
            try require(digest(try Data(contentsOf: input, options: .mappedIfSafe)) == original,
                        "media changed during inspection")
            let silent = videos.count == 1 && audios.isEmpty
            let result: [String: Any] = [
                "schemaVersion": 1, "state": silent ? "SILENT_TRACKS" : "REJECTED_TRACKS",
                "inputSHA256": original, "tracks": inventory,
                "videoTrackCount": videos.count, "audioTrackCount": audios.count,
                "nativeAcceptance": false, "decodedFrames": false
            ]
            try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                .write(to: output, options: [.withoutOverwriting])
            if !silent { exit(2) }
        } catch {
            FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8))
            exit(1)
        }
    }
}
