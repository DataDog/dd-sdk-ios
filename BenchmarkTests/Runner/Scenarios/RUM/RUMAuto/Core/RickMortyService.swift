/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

enum RickMortyError: Error {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case unknown
}

class RickMortyService {
    static let shared = RickMortyService()
    private let baseURL = "https://rickandmortyapi.com/api"
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Characters

    /// Retrieves a list of characters from the Rick and Morty API.
    /// - Parameter nextPageURL: Optional URL for the next page of results.
    /// - Returns: Tuple containing the characters and the URL for the next page.
    func fetchCharacters(nextPageURL: String? = nil) async throws -> (characters: [Character], nextPageURL: String?) {
        let urlString = nextPageURL ?? "\(baseURL)/character"
        guard let url = URL(string: urlString) else {
            throw RickMortyError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try decoder.decode(CharacterResponse.self, from: data)
            return (response.results, response.info.next)
        } catch let error as DecodingError {
            throw RickMortyError.decodingError(error)
        } catch {
            throw RickMortyError.networkError(error)
        }
    }

    // MARK: - Episodes

    /// Retrieves a list of episodes from the Rick and Morty API.
    /// - Parameter nextPageURL: Optional URL for the next page of results.
    /// - Returns: Tuple containing the episodes and the URL for the next page.
    func fetchEpisodes(nextPageURL: String? = nil) async throws -> (episodes: [Episode], nextPageURL: String?) {
        let urlString = nextPageURL ?? "\(baseURL)/episode"
        guard let url = URL(string: urlString) else {
            throw RickMortyError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try decoder.decode(EpisodeResponse.self, from: data)
            return (response.results, response.info.next)
        } catch let error as DecodingError {
            throw RickMortyError.decodingError(error)
        } catch {
            throw RickMortyError.networkError(error)
        }
    }

    /// Fetches multiple episodes by their IDs.
    /// - Parameter ids: Array of episode IDs to fetch.
    /// - Returns: Array of Episode objects.
    func fetchEpisodes(ids: [Int]) async throws -> [Episode] {
        let idsString = ids.map(String.init).joined(separator: ",")
        guard let url = URL(string: "\(baseURL)/episode/\(idsString)") else {
            throw RickMortyError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if ids.count == 1 {
                let episode = try decoder.decode(Episode.self, from: data)
                return [episode]
            } else {
                return try decoder.decode([Episode].self, from: data)
            }
        } catch let error as DecodingError {
            throw RickMortyError.decodingError(error)
        } catch {
            throw RickMortyError.networkError(error)
        }
    }

    /// Fetches all episodes for a given character.
    /// - Parameter character: The character whose episodes should be fetched.
    /// - Returns: Array of Episode objects.
    func fetchEpisodesForCharacter(_ character: Character) async throws -> [Episode] {
        let episodeIds = character.episode.compactMap { url -> Int? in
            guard let id = url.split(separator: "/").last else {
                 return nil
            }
            return Int(id)
        }
        return try await fetchEpisodes(ids: episodeIds)
    }

    // MARK: - Locations

    /// Retrieves a list of locations from the Rick and Morty API.
    /// - Parameter nextPageURL: Optional URL for the next page of results.
    /// - Returns: Tuple containing the locations and the URL for the next page.
    func fetchLocations(nextPageURL: String? = nil) async throws -> (locations: [Location], nextPageURL: String?) {
        let urlString = nextPageURL ?? "\(baseURL)/location"
        guard let url = URL(string: urlString) else {
            throw RickMortyError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try decoder.decode(LocationResponse.self, from: data)
            return (response.results, response.info.next)
        } catch let error as DecodingError {
            throw RickMortyError.decodingError(error)
        } catch {
            throw RickMortyError.networkError(error)
        }
    }

    /// Fetches characters by their IDs.
    /// - Parameter ids: Array of character IDs to fetch.
    /// - Returns: Array of Character objects.
    func fetchCharactersByIds(_ ids: [Int]) async throws -> [Character] {
        guard !ids.isEmpty else {
            return []
        }

        let idsString = ids.map(String.init).joined(separator: ",")
        guard let url = URL(string: "\(baseURL)/character/\(idsString)") else {
            throw RickMortyError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if ids.count == 1 {
                let character = try decoder.decode(Character.self, from: data)
                return [character]
            } else {
                return try decoder.decode([Character].self, from: data)
            }
        } catch let error as DecodingError {
            throw RickMortyError.decodingError(error)
        } catch {
            throw RickMortyError.networkError(error)
        }
    }
}
