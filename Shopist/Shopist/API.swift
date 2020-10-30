/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Alamofire
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

internal struct Category: Decodable {
    let id: String
    let title: String
    let cover: URL
}

internal struct Product: Decodable, Equatable {
    let name: String
    let price: String
    let cover: URL
    let id: Int
    let isInStock: Bool
}

internal struct Payment: Encodable {
    struct Checkout: Encodable {
        let cardNumber: String
        let cvc: Int
        let exp: String

        init() {
            cardNumber = "\(Self.random(length: 16))"
            cvc = Self.random(length: 3)
            exp = "\(Int.random(in: 1...12))/\(Int.random(in: 21...30))"
        }

        private static func random(length: UInt8) -> Int {
            let max = Int(pow(10.0, Double(length)))
            let min = max / 10
            let output = Int.random(in: min..<max)
            return output
        }
    }
    let checkout = Checkout()

    struct Response: Decodable {
        let id: String?
        let cartID: String?
        let cardNumber: String
        let cvc: Int
        let exp: String
        let email: String
        let createdAt: String
        let updatedAt: String
    }
}

internal final class ShopistSessionDelegate: DDURLSessionDelegate, EventMonitor {
    override func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let anError = error ?? fakeError(onceIn: 50)
        super.urlSession(session, task: task, didCompleteWithError: anError)
    }
}

internal final class API {
    // swiftlint:disable force_cast
    static let baseHost = Bundle.main.object(forInfoDictionaryKey: "ShopistBaseURL") as! String
    // swiftlint:enable force_cast
    private static let baseURL = "https://" + baseHost
    private static let apiURL = "https://api." + baseHost

    typealias Completion<T: Decodable> = (Result<T, Error>) -> Void
    let httpClient = Alamofire.Session(
        configuration: .default,
        startRequestsImmediately: false,
        eventMonitors: [ShopistSessionDelegate()]
    )
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func getCategories(completion: @escaping Completion<[Category]>) {
        let urlString = "\(Self.baseURL)/categories.json"
        make(request: URLRequest(urlString), isFailable: false, completion: completion)

        fakeUpdateInfoCall()
        fakeFetchFontCall()
    }

    func getItems(for category: Category, completion: @escaping Completion<[Product]>) {
        let categoryID = category.id
        let urlString = "\(Self.baseURL)/category_\(categoryID).json"
        make(request: URLRequest(urlString), isFailable: true, completion: completion)

        fakeUpdateInfoCall()
        fakeFetchFontCall()
    }

    func checkout(with discountCode: String?, payment: Payment = Payment(), completion: @escaping Completion<Payment.Response>) {
        var url = "\(Self.apiURL)/checkout.json"
        if let someCode = discountCode {
            url.append("?coupon_code=\(someCode)")
        }
        // swiftlint:disable force_try
        var request = try! URLRequest(url: url, method: .post)
        request.httpBody = try! jsonEncoder.encode(payment)
        // swiftlint:enable force_try
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        make(request: request, isFailable: true, completion: completion)
    }

    private func make<T: Decodable>(request: URLRequest, isFailable: Bool, completion: @escaping Completion<T>) {
        httpClient
            .request(request)
            .validate()
            .response { result in
                if let someError = result.error {
                    completion(.failure(someError))
                } else if let someData = result.data {
                    let completionResult: Result<T, Error>
                    do {
                        Thread.sleep(for: .short)
                        let decoded = try self.jsonDecoder.decode(T.self, from: someData)
                        completionResult = .success(decoded)
                    } catch {
                        completionResult = .failure(error)
                    }
                    completion(completionResult)
                }
            }
            .resume()
    }

    func fakeFetchShippingAndTax() {
        let shippingURL = URL(string: "\(Self.apiURL)/shipping_tax.json")! // swiftlint:disable:this force_unwrapping
        DispatchQueue.global(qos: .utility).async {
            Thread.sleep(for: .short)
            let resourceKey = shippingURL.pathComponents.joined()
            Global.rum.startResourceLoading(
                resourceKey: resourceKey,
                url: shippingURL,
                httpMethod: .GET
            )
            Thread.sleep(for: .short)
            Global.rum.stopResourceLoadingWithError(
                resourceKey: resourceKey,
                errorMessage: "Shipping and taxes cannot be fetched from server"
            )
        }
    }

    func fakeFetchFontCall() {
        let fontURL = URL(string: "\(Self.apiURL)/fonts/crimsontext_regular.ttf")! // swiftlint:disable:this force_unwrapping
        DispatchQueue.global(qos: .utility).async {
            Thread.sleep(for: .short)
            let resourceKey = fontURL.pathComponents.joined()
            Global.rum.startResourceLoading(
                resourceKey: resourceKey,
                url: fontURL,
                httpMethod: .GET
            )
            Thread.sleep(for: .long)
            Global.rum.stopResourceLoading(
                resourceKey: resourceKey,
                kind: .font,
                httpStatusCode: 200,
                size: Int64.random(in: 128...256) * 1_000
            )
        }
    }

    func fakeUpdateInfoCall() {
        let updateInfoURL = URL(string: "\(Self.apiURL)/update_info")! // swiftlint:disable:this force_unwrapping force_unwrapping
        DispatchQueue.global(qos: .utility).async {
            Thread.sleep(for: .short)
            let resourceKey = updateInfoURL.pathComponents.joined()
            Global.rum.startResourceLoading(
                resourceKey: resourceKey,
                url: updateInfoURL,
                httpMethod: .POST
            )
            Thread.sleep(for: .medium)
            Global.rum.stopResourceLoading(
                resourceKey: resourceKey,
                kind: .xhr,
                httpStatusCode: 200,
                size: Int64.random(in: 1_024...4_096)
            )
        }
    }
}

private extension URLRequest {
    init(_ string: String) {
        self = URLRequest(url: URL(string: string)!) // swiftlint:disable:this force_unwrapping
    }
}
