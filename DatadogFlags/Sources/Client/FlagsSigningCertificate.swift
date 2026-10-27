/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal enum FlagsSigningError: String, Error {
    case unsupportedRequest, missingAnchor, missingProof, invalidProof
    case invalidCertificate, invalidSignature, expiredProof, responseTooLarge
}

/// Bounded DER for the deliberately restricted assignment-signing certificate profile.
/// This is not a general PKIX path builder and never discovers trust from a response.
internal struct FlagsSigningDER {
    let tag: UInt8
    let raw: Data
    let content: Data
    let children: [FlagsSigningDER]

    static func parse(_ data: Data) throws -> FlagsSigningDER {
        guard !data.isEmpty, data.count <= 4_096 else {
            throw FlagsSigningError.invalidCertificate
        }
        let bytes = Array(data)
        var offset = 0
        var nodes = 0
        func read(limit: Int, depth: Int) throws -> FlagsSigningDER {
            guard depth <= 24, nodes < 512, offset + 2 <= limit else {
                throw FlagsSigningError.invalidCertificate
            }
            nodes += 1
            let beginning = offset
            let tag = bytes[offset]
            offset += 1
            guard tag & 31 != 31 else {
                throw FlagsSigningError.invalidCertificate
            }
            var length = Int(bytes[offset])
            offset += 1
            if length & 128 != 0 {
                let count = length & 127
                guard count > 0, count <= 3, offset + count <= limit, bytes[offset] != 0 else {
                    throw FlagsSigningError.invalidCertificate
                }
                length = 0
                for _ in 0..<count {
                    length = length * 256 + Int(bytes[offset])
                    offset += 1
                }
                guard length >= 128 else {
                    throw FlagsSigningError.invalidCertificate
                }
            }
            let start = offset
            let end = start + length
            guard end <= limit else {
                throw FlagsSigningError.invalidCertificate
            }
            var children: [FlagsSigningDER] = []
            if tag & 32 != 0 {
                guard tag & 192 != 0 || tag == 48 || tag == 49 else {
                    throw FlagsSigningError.invalidCertificate
                }
                while offset < end { children.append(try read(limit: end, depth: depth + 1)) }
                if tag == 49 {
                    for index in 1..<max(1, children.count) {
                        guard !children[index].raw.lexicographicallyPrecedes(children[index - 1].raw) else {
                            throw FlagsSigningError.invalidCertificate
                        }
                    }
                }
            } else {
                offset = end
                switch tag {
                case 1:
                    guard length == 1, bytes[start] == 0 || bytes[start] == 255 else {
                        throw FlagsSigningError.invalidCertificate
                    }
                case 2:
                    guard length > 0 else {
                        throw FlagsSigningError.invalidCertificate
                    }
                    if length > 1 {
                        guard !(bytes[start] == 0 && bytes[start + 1] & 128 == 0),
                            !(bytes[start] == 255 && bytes[start + 1] & 128 != 0)
                        else {
                            throw FlagsSigningError.invalidCertificate
                        }
                    }
                case 3:
                    guard length > 0, bytes[start] <= 7,
                        length > 1 || bytes[start] == 0,
                        bytes[end - 1] & UInt8((1 << Int(bytes[start])) - 1) == 0
                    else {
                        throw FlagsSigningError.invalidCertificate
                    }
                case 5:
                    guard length == 0 else {
                        throw FlagsSigningError.invalidCertificate
                    }
                case 6:
                    guard length > 0, bytes[end - 1] & 128 == 0 else {
                        throw FlagsSigningError.invalidCertificate
                    }
                    for index in start..<end where bytes[index] == 128 {
                        guard index > start, bytes[index - 1] & 128 != 0 else {
                            throw FlagsSigningError.invalidCertificate
                        }
                    }
                default: break
                }
            }
            return FlagsSigningDER(
                tag: tag,
                raw: Data(bytes[beginning..<end]),
                content: Data(bytes[start..<end]),
                children: children
            )
        }
        let result = try read(limit: bytes.count, depth: 0)
        guard offset == bytes.count else {
            throw FlagsSigningError.invalidCertificate
        }
        return result
    }
}

internal struct FlagsSigningCertificate {
    enum Role { case leaf, intermediate, anchor }
    let tbs: Data
    let signature: Data
    let publicKey: Data
    let subject: Data
    let issuer: Data
    let notBefore: TimeInterval
    let notAfter: TimeInterval
    let subjectKeyID: Data?
    let authorityKeyID: Data?

    private static let signatureAlgorithm = Data([48, 10, 6, 8, 42, 134, 72, 206, 61, 4, 3, 2])
    private static let publicKeyAlgorithm = Data([
        48, 19, 6, 7, 42, 134, 72, 206, 61, 2, 1, 6, 8, 42, 134, 72, 206, 61, 3, 1, 7
    ])
    private static let codeSigning = Data([48, 10, 6, 8, 43, 6, 1, 5, 5, 7, 3, 3])

    init(der: Data, role: Role) throws {
        let outer = try FlagsSigningDER.parse(der)
        guard outer.tag == 48, outer.children.count == 3 else {
            throw FlagsSigningError.invalidCertificate
        }
        let fields = outer.children[0].children
        guard outer.children[0].tag == 48, fields.count == 7 || fields.count == 8,
            fields[0].raw == Data([160, 3, 2, 1, 2]),
            fields[1].tag == 2, !fields[1].content.isEmpty, fields[1].content.count <= 20,
            let serialFirst = fields[1].content.first, serialFirst & 128 == 0,
            fields[1].content.contains(where: { $0 != 0 }),
            fields[2].raw == Self.signatureAlgorithm,
            outer.children[1].raw == Self.signatureAlgorithm,
            outer.children[2].tag == 3, outer.children[2].content.first == 0,
            fields[3].tag == 48, fields[5].tag == 48,
            fields[4].tag == 48, fields[4].children.count == 2,
            fields[6].tag == 48, fields[6].children.count == 2,
            fields[6].children[0].raw == Self.publicKeyAlgorithm,
            fields[6].children[1].tag == 3, fields[6].children[1].content.count == 66,
            fields[6].children[1].content.first == 0
        else {
            throw FlagsSigningError.invalidCertificate
        }
        try Self.validateName(fields[3])
        try Self.validateName(fields[5])
        tbs = outer.children[0].raw
        signature = Data(outer.children[2].content.dropFirst())
        try Self.validateSignature(signature)
        publicKey = Data(fields[6].children[1].content.dropFirst())
        guard publicKey.first == 4 else {
            throw FlagsSigningError.invalidCertificate
        }
        issuer = fields[3].raw
        subject = fields[5].raw
        notBefore = try Self.date(fields[4].children[0])
        notAfter = try Self.date(fields[4].children[1])
        guard notBefore < notAfter else {
            throw FlagsSigningError.invalidCertificate
        }
        var extensions: [Data: (critical: Bool, value: Data)] = [:]
        var extensionItems: [FlagsSigningDER] = []
        if fields.count == 8 {
            guard fields[7].tag == 163, fields[7].children.count == 1, fields[7].children[0].tag == 48 else {
                throw FlagsSigningError.invalidCertificate
            }
            extensionItems = fields[7].children[0].children
        }
        for item in extensionItems {
            guard item.tag == 48, item.children.count == 2 || item.children.count == 3,
                item.children[0].tag == 6
            else {
                throw FlagsSigningError.invalidCertificate
            }
            let oid = item.children[0].content
            let critical = item.children.count == 3
            if critical {
                guard item.children[1].raw == Data([1, 1, 255]) else {
                    throw FlagsSigningError.invalidCertificate
                }
            }
            guard let value = item.children.last, value.tag == 4, extensions[oid] == nil else {
                throw FlagsSigningError.invalidCertificate
            }
            _ = try FlagsSigningDER.parse(value.content)
            guard ![Data([85, 29, 30]), Data([85, 29, 36]), Data([85, 29, 54])].contains(oid) else {
                throw FlagsSigningError.invalidCertificate
            }
            let understood = [19, 15, 37, 14, 35].map { Data([85, 29, UInt8($0)]) }
            guard !critical || understood.contains(oid) else {
                throw FlagsSigningError.invalidCertificate
            }
            extensions[oid] = (critical, value.content)
        }
        if role != .anchor {
            guard let basic = extensions[Data([85, 29, 19])], basic.critical,
                let usage = extensions[Data([85, 29, 15])], usage.critical,
                basic.value == (role == .leaf ? Data([48, 0]) : Data([48, 6, 1, 1, 255, 2, 1, 0])),
                usage.value == (role == .leaf ? Data([3, 2, 7, 128]) : Data([3, 2, 1, 6]))
            else {
                throw FlagsSigningError.invalidCertificate
            }
        }
        let purpose = extensions[Data([85, 29, 37])]
        guard role != .leaf || purpose != nil else {
            throw FlagsSigningError.invalidCertificate
        }
        if let purpose, purpose.value != Self.codeSigning {
            throw FlagsSigningError.invalidCertificate
        }
        if let ski = extensions[Data([85, 29, 14])] {
            let parsed = try FlagsSigningDER.parse(ski.value)
            guard parsed.tag == 4 else {
                throw FlagsSigningError.invalidCertificate
            }
            subjectKeyID = parsed.content
        } else {
            subjectKeyID = nil
        }
        if let aki = extensions[Data([85, 29, 35])] {
            let parsed = try FlagsSigningDER.parse(aki.value)
            guard parsed.tag == 48, parsed.children.count <= 1,
                parsed.children.allSatisfy({ $0.tag == 128 })
            else {
                throw FlagsSigningError.invalidCertificate
            }
            authorityKeyID = parsed.children.first?.content
        } else {
            authorityKeyID = nil
        }
    }

    func validateLink(to parent: FlagsSigningCertificate) throws {
        guard issuer == parent.subject, notBefore >= parent.notBefore, notAfter <= parent.notAfter else {
            throw FlagsSigningError.invalidCertificate
        }
        if let authorityKeyID, let ski = parent.subjectKeyID, authorityKeyID != ski {
            throw FlagsSigningError.invalidCertificate
        }
    }

    static func validateSignature(_ data: Data) throws {
        guard data.count >= 8, data.count <= 72 else {
            throw FlagsSigningError.invalidSignature
        }
        let parsed = try FlagsSigningDER.parse(data)
        guard parsed.tag == 48, parsed.children.count == 2 else {
            throw FlagsSigningError.invalidSignature
        }
        for value in parsed.children {
            guard value.tag == 2, let first = value.content.first, first & 128 == 0,
                value.content.count <= (first == 0 ? 33 : 32), value.content.contains(where: { $0 != 0 })
            else {
                throw FlagsSigningError.invalidSignature
            }
        }
    }

    private static func validateName(_ name: FlagsSigningDER) throws {
        for set in name.children {
            guard set.tag == 49, !set.children.isEmpty else {
                throw FlagsSigningError.invalidCertificate
            }
            for pair in set.children {
                guard pair.tag == 48, pair.children.count == 2, pair.children[0].tag == 6 else {
                    throw FlagsSigningError.invalidCertificate
                }
            }
        }
    }

    private static func date(_ value: FlagsSigningDER) throws -> TimeInterval {
        guard let string = String(data: value.content, encoding: .ascii),
            string.last == "Z", value.tag == 23 || value.tag == 24,
            string.count == (value.tag == 23 ? 13 : 15),
            string.dropLast().allSatisfy({ $0.isASCII && $0.isNumber })
        else {
            throw FlagsSigningError.invalidCertificate
        }
        let full: String
        if value.tag == 23 {
            guard let year = Int(string.prefix(2)) else {
                throw FlagsSigningError.invalidCertificate
            }
            full = (year >= 50 ? "19" : "20") + string
        } else {
            full = string
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        formatter.isLenient = false
        guard let date = formatter.date(from: full), formatter.string(from: date) == full else {
            throw FlagsSigningError.invalidCertificate
        }
        return date.timeIntervalSince1970
    }
}
