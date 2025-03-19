/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

struct CharactersView: View {
    @State private var characters: [Character] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var nextPageURL: String?

    var body: some View {
        NavigationView {
            Group {
                if characters.isEmpty {
                    Text("No characters. Should not happen :/")
                } else if isLoading {
                    ProgressView()
                } else if let error {
                    Text("Error: \(error.localizedDescription)")
                } else {
                    List {
                        ForEach(characters) { character in
                            NavigationLink(destination: CharacterDetailView(character: character)) {
                                CharacterListItem(character: character)
                            }
                            .onAppear {
                                loadMoreIfNeeded(currentItem: character)
                            }
                        }

                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("Characters")
            .tint(.purple)
            .onAppear {
                if characters.isEmpty {
                    Task {
                        await fetchCharacters()
                    }
                }
            }
        }
    }

    /// Loads character data using the RickMortyService.
    private func fetchCharacters() async {
        if nextPageURL == nil {
            error = nil
        }

        isLoading = true

        do {
            let result = try await RickMortyService.shared.fetchCharacters(nextPageURL: nextPageURL)
            if nextPageURL == nil {
                characters = result.characters
            } else {
                characters.append(contentsOf: result.characters)
            }
            nextPageURL = result.nextPageURL
        } catch {
            if nextPageURL == nil {
                self.error = error
            }
        }

        isLoading = false
    }

    /// Determines if more characters need to be loaded based on current scroll position.
    /// - Parameter currentItem: The character item that just appeared in the view.
    private func loadMoreIfNeeded(currentItem: Character) {
        let thresholdIndex = characters.count - 3
        guard thresholdIndex >= 0,
              let currentIndex = characters.firstIndex(where: { $0.id == currentItem.id }),
              currentIndex >= thresholdIndex,
              !isLoading,
              nextPageURL != nil else { return }

        Task {
            await fetchCharacters()
        }
    }
}

#Preview {
    CharactersView()
}
