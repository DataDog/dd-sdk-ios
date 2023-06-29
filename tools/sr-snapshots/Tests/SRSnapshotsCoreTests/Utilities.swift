/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import SRSnapshotsCore

struct HashingMock: Hashing {
    private var hashes: [String: String] = [:]

    init(_ hashes: [String: String]) {
        self.hashes = hashes
    }

    func hash(from data: Data) -> String {
        return hashes[data.utf8String] ?? "(not set in mock)"
    }
}

func mockRandomFiles(count: Int) -> [String: String] {
    var files: [String: String] = [:]
    (0..<count).forEach { _ in files[mockRandomPath()] = UUID().uuidString }
    return files
}

func mockRandomPath(extension: String? = nil) -> String {
    let count = Int.random(in: (1..<10))
    let components = (0..<count).map { _ in UUID().uuidString.prefix(3) }
    return "/" + components.joined(separator: "/") + (`extension`.map({ "." + $0 }) ?? "")
}

internal extension Data {
    var utf8String: String { String(data: self, encoding: .utf8)! }
}

internal extension String {
    var utf8Data: Data { self.data(using: .utf8)! }
}
