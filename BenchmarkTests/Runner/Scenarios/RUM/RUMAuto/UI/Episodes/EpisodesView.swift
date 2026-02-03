/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftUI

struct EpisodesView: View {
    @State private var episodes: [Episode] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var nextPageURL: String?

    var body: some View {
        NavigationView {
            Group {
                if episodes.isEmpty {
                    Text("No episodes. Should not happen :/")
                } else if let error {
                    Text("Error: \(error.localizedDescription)")
                } else {
                    List {
                        ForEach(episodes) { episode in
                            NavigationLink(destination: EpisodeDetailHostingController(episode: episode)) {
                                EpisodeListItem(episode: episode)
                            }
                            .onAppear {
                                loadMoreIfNeeded(currentItem: episode)
                            }
                        }

                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Episodes")
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK", role: .cancel) {
                    error = nil
                }
            } message: {
                Text(error?.localizedDescription ?? "An unknown error occurred")
            }
            .onAppear {
                if episodes.isEmpty {
                    Task {
                        await fetchEpisodes()
                    }
                }
            }
        }
    }

    private func loadMoreIfNeeded(currentItem: Episode) {
        let thresholdIndex = episodes.count - 3
        guard thresholdIndex >= 0,
              let currentIndex = episodes.firstIndex(where: { $0.id == currentItem.id }),
              currentIndex >= thresholdIndex,
              !isLoading,
              nextPageURL != nil else { return }

        Task {
            await fetchEpisodes()
        }
    }

    private func fetchEpisodes() async {
        if nextPageURL == nil {
            error = nil
        }

        isLoading = true

        do {
            let result = try await RickMortyService.shared.fetchEpisodes(nextPageURL: nextPageURL)
            if nextPageURL == nil {
                episodes = result.episodes
            } else {
                episodes.append(contentsOf: result.episodes)
            }
            nextPageURL = result.nextPageURL
        } catch {
            if nextPageURL == nil {
                self.error = error
            }
        }

        isLoading = false
    }
}

#Preview {
    EpisodesView()
}
