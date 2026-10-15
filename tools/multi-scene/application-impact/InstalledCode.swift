/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CryptoKit

enum InstalledCodeReceipt {
    static func writeIfRequested(runID: String) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let requestedRun = environment["MULTISCENE_CODE_IDENTITY_RUN_ID"] else {
            return
        }
        let revision = environment["MULTISCENE_CODE_IDENTITY_REVISION"] ?? ""
        guard requestedRun == runID,
              runID.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil,
              revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              let executable = Bundle.main.executableURL,
              let bundleID = Bundle.main.bundleIdentifier else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let manager = FileManager.default
        let documents = try manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let receipt = documents.appendingPathComponent(runID + ".installed-code.json")
        guard !manager.fileExists(atPath: receipt.path) else { throw CocoaError(.fileWriteFileExists) }
        let root = Bundle.main.bundleURL
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let files = manager.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw CocoaError(.fileReadUnknown)
        }
        var hashes: [String: String] = [:]
        for case let file as URL in files {
            let properties = try file.resourceValues(forKeys: Set(keys))
            guard properties.isRegularFile == true, properties.isSymbolicLink != true else { continue }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 4) ?? Data()
            let magic = header.map { String(format: "%02x", $0) }.joined()
            guard ["cffaedfe", "feedfacf", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"].contains(magic) else {
                continue
            }
            var digest = SHA256()
            digest.update(data: header)
            while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                digest.update(data: chunk)
            }
            let relative = String(file.path.dropFirst(root.path.count + 1))
            hashes[relative] = digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
        let mainPath = String(executable.path.dropFirst(root.path.count + 1))
        guard hashes[mainPath] != nil else { throw CocoaError(.fileReadCorruptFile) }
        let value: [String: Any] = [
            "schemaVersion": 1, "runID": runID, "sourceRevision": revision,
            "processID": ProcessInfo.processInfo.processIdentifier, "bundleIdentifier": bundleID,
            "boundary": "before-sdk-initialization", "executable": mainPath, "binaries": hashes
        ]
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: receipt, options: .atomic)
    }
}
