/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Alamofire

struct Category: Decodable {
    let id: String
    let title: String
    let cover: URL
}

struct Product: Decodable {
    let name: String
    let price: String
    let cover: URL
    let id: Int
    let isInStock: Bool
}

final class API {
    private static let baseURL = "https://" + (Bundle.main.object(forInfoDictionaryKey: "ShopistBaseURL") as! String)
    typealias Completion<T: Decodable> = (Result<T, Error>) -> Void
    private let httpClient = Alamofire.Session(configuration: .default)
    private let jsonDecoder = JSONDecoder()

    func getCategories(completion: @escaping Completion<[Category]>) {
        get("\(Self.baseURL)/categories.json", completion: completion)
    }

    func getItems(for category: Category, completion: @escaping Completion<[Product]>) {
        let categoryID = category.id
        let urlString = "\(Self.baseURL)/category_\(categoryID).json"
        get(urlString, completion: completion)
    }

    private func get<T: Decodable>(_ urlString: String, completion: @escaping Completion<T>) {
        guard let url = URL(string: urlString) else {
            fatalError("\(urlString) is not a valid URL!")
        }
        let request = URLRequest(url: url)

        httpClient.request(request).response { response in
            if let someError = response.error {
                completion(.failure(someError))
            } else if let someData = response.data {
                do {
                    let decoded = try self.jsonDecoder.decode(T.self, from: someData)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            } else {
                // Datadog.log maybe?
                print("Unknown case")
            }
        }
    }
}
