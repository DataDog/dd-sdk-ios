/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import AVKit
import SwiftUI

@available(iOS 16.0, *)
internal struct VideoPlayerFixtureView: View {
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .frame(width: 320, height: 180)
            .task {
                let url = Bundle(for: LayerSnapshotTestCase.self)
                    .url(forResource: "four-colors", withExtension: "mp4")!
                player = AVPlayer(url: url)
            }
    }
}
