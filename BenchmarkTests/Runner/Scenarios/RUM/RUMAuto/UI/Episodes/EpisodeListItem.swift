/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

struct EpisodeListItem: View {
    let episode: Episode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(episode.name)
                .font(.headline)

            HStack {
                Text(episode.episode)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text(episode.airDate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
