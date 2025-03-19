/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import UIKit

struct EpisodeDetailHostingController: UIViewControllerRepresentable {
    let episode: Episode

    func makeUIViewController(context _: Context) -> UINavigationController {
        let storyboard = UIStoryboard(name: "EpisodeDetailView", bundle: nil)
        if let detailVC = storyboard.instantiateViewController(withIdentifier: "EpisodeDetail") as? EpisodeDetailViewController {
            detailVC.episode = episode
            let navigationController = UINavigationController(rootViewController: detailVC)
            navigationController.navigationBar.isHidden = true
            return navigationController
        }
        return UINavigationController()
    }

    func updateUIViewController(_: UINavigationController, context _: Context) {}
}
