/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

internal func fakeError(onceIn upperRandomBound: UInt8) -> Error? {
    assert(upperRandomBound != 0, "fakeError can be generated with non-zero positive numbers")
    if UInt8.random(in: 0..<upperRandomBound) == 0 {
        return NSError(
            domain: "Network",
            code: 999,
            userInfo: [NSLocalizedDescriptionKey: "Request denied"]
        )
    }
    return nil
}

/// A set of API extension methods used to fake certain requests and responses.
internal protocol APIFakeRequests {
    func fakeFetchShippingAndTax()
    func fakeFetchFontCall()
    func fakeUpdateInfoCall()
}

// swiftlint:disable force_unwrapping force_try
extension APIFakeRequests {
    func fakeFetchShippingAndTax() {
        let shippingURL = URL(string: "\(API.apiURL)/shipping_tax.json")!
        DispatchQueue.global(qos: .utility).async {
            Thread.sleep(for: .short)
            let resourceKey = shippingURL.pathComponents.joined()
            Global.rum.startResourceLoading(
                resourceKey: resourceKey,
                request: try! URLRequest(url: shippingURL, method: .get)
            )
            Thread.sleep(for: .short)
            Global.rum.stopResourceLoadingWithError(
                resourceKey: resourceKey,
                errorMessage: "Shipping and taxes cannot be fetched from server"
            )
        }
    }

    func fakeFetchFontCall() {
        let fontURL = URL(string: "\(API.apiURL)/fonts/crimsontext_regular.ttf")!
        DispatchQueue.global(qos: .utility).async {
            Thread.sleep(for: .short)
            let resourceKey = fontURL.pathComponents.joined()
            Global.rum.startResourceLoading(
                resourceKey: resourceKey,
                request: try! URLRequest(url: fontURL, method: .get)
            )
            Thread.sleep(for: .long)
            Global.rum.stopResourceLoading(
                resourceKey: resourceKey,
                response: HTTPURLResponse(
                    url: fontURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "font/ttf"]
                )!,
                size: Int64.random(in: 128...256) * 1_000
            )
        }
    }

    func fakeUpdateInfoCall() {
        let updateInfoURL = URL(string: "\(API.apiURL)/update_info")!
        DispatchQueue.global(qos: .utility).async {
            Thread.sleep(for: .short)
            let resourceKey = updateInfoURL.pathComponents.joined()
            let request = try! URLRequest(url: updateInfoURL, method: .post)
            Global.rum.startResourceLoading(
                resourceKey: resourceKey,
                request: request
            )
            Thread.sleep(for: .medium)
            Global.rum.stopResourceLoading(
                resourceKey: resourceKey,
                response: HTTPURLResponse(
                    url: updateInfoURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                request: request,
                size: Int64.random(in: 1_024...4_096)
            )
        }
    }
}
// swiftlint:enable force_unwrapping force_try
