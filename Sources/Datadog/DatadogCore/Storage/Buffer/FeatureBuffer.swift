/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct FeatureBuffer {

    let url: URL
    
    let pendingURL: URL

    let queue: DispatchQueue

    /// JSON encoder used to encode data.
    let encoder: JSONEncoder

    let encryption: DataEncryption?

    var reader: BufferReader {
        .init(file: url, queue: queue, encryption: encryption)
    }

    init(
        name: String,
        directory: URL,
        queue: DispatchQueue,
        encoder: JSONEncoder = .default(),
        encryption: DataEncryption? = nil
    ) throws {
        self.url = directory.appendingPathComponent(name)
            .appendingPathExtension("granted")
        self.pendingURL = directory.appendingPathComponent(name)
            .appendingPathExtension("pending")

        self.queue = queue
        self.encoder = encoder
        self.encryption = encryption

        let fs = FileManager.default
        if !fs.fileExists(atPath: url.path) {
            fs.createFile(atPath: url.path, contents: nil)
        }

        if !fs.fileExists(atPath: pendingURL.path) {
            fs.createFile(atPath: pendingURL.path, contents: nil)
        }
    }

    func writer(for consent: TrackingConsent) -> Writer {
        switch consent {
        case .granted:
            return BufferWriter(
                file: url,
                queue: queue,
                encoder: encoder,
                encryption: encryption
            )
        case .notGranted:
            return NOPWriter()
        case .pending:
            return BufferWriter(
                file: pendingURL,
                queue: queue,
                encoder: encoder,
                encryption: encryption
            )
        }
    }

    func update(consent: TrackingConsent) {
        guard consent != .pending else {
            return
        }

        queue.async {
            let fs = FileManager.default

            switch consent {
            case .granted:
                var data = fs.contents(atPath: url.path) ?? Data()
                data += fs.contents(atPath: pendingURL.path) ?? Data()
                // TODO: Telemetry
                try? data.write(to: url, options: .atomic)

            case .notGranted:
                // TODO: Telemetry
                try? fs.removeItem(at: url)
                try? fs.removeItem(at: pendingURL)

            default:
                return
            }
        }
    }
}
