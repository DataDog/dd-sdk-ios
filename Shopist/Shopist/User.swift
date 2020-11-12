/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

private extension UInt8 {
    static func randomByte(
        in range: ClosedRange<UInt8> = UInt8.min...UInt8.max,
        except: Set<UInt8> = []
    ) -> UInt8 {
        while true {
            let byte = UInt8.random(in: range)
            if !except.contains(byte) {
                return byte
            }
        }
    }
}

private extension String {
    static func randomIPv4() -> Self {
        let bytes: [UInt8] = [
            UInt8.randomByte(in: 1...223, except: [10, 100, 127, 169, 172, 192, 198, 203]),
            UInt8.randomByte(),
            UInt8.randomByte(),
            UInt8.randomByte()
        ]
        return bytes.map(String.init).joined(separator: ".")
    }
}

internal struct User {
    let id: String = UUID().uuidString
    let name: String
    let ipAddress = String.randomIPv4()
    var email: String {
        return name.lowercased()
            .replacingOccurrences(of: " ", with: "@")
            .appending(".com")
    }

    static let users: [User] = [
        User(name: "John Doe"),
        User(name: "Jane Doe"),
        User(name: "Pat Doe"),
        User(name: "Sam Doe"),
        User(name: "Maynard Keenan"),
        User(name: "Adam Jones"),
        User(name: "Justin Chancellor"),
        User(name: "Danny Carey"),
        User(name: "Karina Round"),
        User(name: "Martin Lopez"),
        User(name: "Anneke Giersbergen"),
        User(name: "Billie Eilish"),
        User(name: "Cardi B"),
        User(name: "Nicki Minaj"),
        User(name: "Beyonce Knowles")
    ]

    private static let userDefaultsUserIndexKey = "shopist.currentUser.index"
    static func any() -> Self {
        let index = UserDefaults.standard.integer(forKey: userDefaultsUserIndexKey)
        let user = users[index % users.count]
        UserDefaults.standard.set(index + 1, forKey: userDefaultsUserIndexKey)
        return user
    }
}
