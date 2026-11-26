/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Answers Rick & Morty API requests from data bundled in the app, so benchmark runs
/// do not depend on the public API being available.
///
/// Requests still go through `URLSession`: only the transport is replaced, so the app
/// creates and completes real `URLSessionTask`s.
final class RickMortyMockURLProtocol: URLProtocol {
    static let host = "rickandmortyapi.com"

    /// Registers the mock for every request made through `URLSession.shared`.
    static func register() {
        URLProtocol.registerClass(RickMortyMockURLProtocol.self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let answer = RickMortyMockData.shared.answer(for: url)

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: answer.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": answer.contentType]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The bundled dataset and the routing of the Rick & Morty API endpoints used by the app.
final class RickMortyMockData {
    struct Answer {
        let statusCode: Int
        let contentType: String
        let body: Data
    }

    static let shared = RickMortyMockData()

    private let pageSize = 20
    private let baseURL = "https://rickandmortyapi.com/api"
    private let resources: [String: [[String: Any]]]
    private let avatars: [Data]

    private init() {
        resources = [
            "character": Self.loadJSON("RickMortyMockCharacters"),
            "episode": Self.loadJSON("RickMortyMockEpisodes"),
            "location": Self.loadJSON("RickMortyMockLocations"),
        ]
        avatars = (1...3).compactMap { index in
            Bundle.main.url(forResource: "RickMortyMockAvatar\(index)", withExtension: "png")
                .flatMap { try? Data(contentsOf: $0) }
        }
    }

    /// Supports the routes the app uses:
    /// - `/api/{resource}` and `/api/{resource}?page=N`: a page of 20 items
    /// - `/api/{resource}/{id}` and `/api/{resource}/{id},{id}`: an object for one id, an array otherwise
    /// - `/api/character/avatar/{id}.jpeg`: one of the 3 bundled avatars, so each character keeps its own URL
    func answer(for url: URL) -> Answer {
        let path = url.pathComponents.filter { $0 != "/" }

        guard path.first == "api", path.count >= 2, let items = resources[path[1]] else {
            return notFound(url)
        }

        if path.count == 2 {
            return page(of: items, resource: path[1], url: url)
        }

        if path.count == 4, path[1] == "character", path[2] == "avatar" {
            return avatar(named: path[3], url: url)
        }

        if path.count == 3 {
            return lookup(ids: path[2], in: items, url: url)
        }

        return notFound(url)
    }

    // MARK: - Routes

    private func page(of items: [[String: Any]], resource: String, url: URL) -> Answer {
        let pageNumber = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "page" }?
            .value
            .flatMap(Int.init) ?? 1
        let pages = max(1, (items.count + pageSize - 1) / pageSize)

        guard (1...pages).contains(pageNumber) else {
            return notFound(url)
        }

        let start = (pageNumber - 1) * pageSize
        let results = Array(items[start..<min(start + pageSize, items.count)])
        let info: [String: Any] = [
            "count": items.count,
            "pages": pages,
            "next": pageNumber < pages ? "\(baseURL)/\(resource)?page=\(pageNumber + 1)" : NSNull(),
            "prev": pageNumber > 1 ? "\(baseURL)/\(resource)?page=\(pageNumber - 1)" : NSNull(),
        ]
        return json(["info": info, "results": results])
    }

    private func lookup(ids idList: String, in items: [[String: Any]], url: URL) -> Answer {
        let ids = idList.split(separator: ",").compactMap { Int($0) }
        let found = ids.compactMap { id in items.first { ($0["id"] as? Int) == id } }

        guard !found.isEmpty, let first = found.first else {
            return notFound(url)
        }

        return ids.count == 1 ? json(first) : json(found)
    }

    private func avatar(named fileName: String, url: URL) -> Answer {
        guard !avatars.isEmpty, let id = Int(fileName.split(separator: ".").first ?? "") else {
            return notFound(url)
        }

        return Answer(statusCode: 200, contentType: "image/png", body: avatars[(id - 1 + avatars.count) % avatars.count])
    }

    // MARK: - Helpers

    private func json(_ object: Any) -> Answer {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return Answer(statusCode: 200, contentType: "application/json", body: body)
    }

    private func notFound(_ url: URL) -> Answer {
        print("[RickMortyMock] unhandled \(url.absoluteString)")
        let body = Data(#"{"error":"There is nothing here"}"#.utf8)
        return Answer(statusCode: 404, contentType: "application/json", body: body)
    }

    private static func loadJSON(_ name: String) -> [[String: Any]] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("[RickMortyMock] missing bundled data: \(name).json")
            return []
        }
        return items
    }
}
