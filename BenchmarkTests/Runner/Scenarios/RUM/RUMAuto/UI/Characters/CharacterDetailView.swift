/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

struct CharacterDetailView: View {
    let character: Character
    @State private var isLocationsExpanded = false
    @State private var isEpisodesExpanded = false
    @State private var episodes: [Episode] = []
    @State private var isLoadingEpisodes = false

    var body: some View {
        ScrollView {
            VStack {
                // Header Image
                AsyncImage(url: URL(string: character.image)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipped()

                VStack(spacing: 24) {
                    // Basic Info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(character.name)
                                .font(.title)
                                .bold()

                            StatusBadge(status: character.status)
                        }

                        Text(character.species)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Expandable Sections
                    VStack(spacing: 16) {
                        // Locations Section
                        DisclosureGroup(
                            isExpanded: $isLocationsExpanded,
                            content: {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Origin")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text(character.origin.name)
                                            .font(.body)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Current Location")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text(character.location.name)
                                            .font(.body)
                                    }
                                }
                                .padding(.top, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            },
                            label: {
                                Label("Location Information", systemImage: "mappin.circle")
                            }
                        )

                        // Episodes Section
                        DisclosureGroup(
                            isExpanded: $isEpisodesExpanded,
                            content: {
                                if isLoadingEpisodes {
                                    ProgressView()
                                        .padding(.top, 8)
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(episodes) { episode in
                                            Text("\(episode.episode) - \(episode.name)")
                                                .font(.subheadline)
                                        }
                                    }
                                    .padding(.top, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            },
                            label: {
                                Label("Appears in \(character.episode.count) Episodes", systemImage: "tv")
                            }
                        )
                        .onChange(of: isEpisodesExpanded) {
                            if episodes.isEmpty {
                                Task {
                                    await fetchEpisodes()
                                }
                            }
                        }

                        // Additional Info
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(title: "Gender", value: character.gender)
                            if !character.type.isEmpty {
                                InfoRow(title: "Type", value: character.type)
                            }
                            InfoRow(title: "Created", value: formatDate(character.created))
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Fetches episodes for the current character.
    private func fetchEpisodes() async {
        isLoadingEpisodes = true

        do {
            episodes = try await RickMortyService.shared.fetchEpisodesForCharacter(character)
        } catch {
            print("Error fetching episodes: \(error)")
        }

        isLoadingEpisodes = false
    }
}
