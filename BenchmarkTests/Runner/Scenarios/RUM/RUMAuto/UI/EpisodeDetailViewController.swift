/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

class EpisodeDetailViewController: UIViewController {
    // MARK: - Properties

    var episode: Episode?
    private var characters: [Character] = []

    // MARK: - Outlets

    @IBOutlet private var episodeCodeLabel: UILabel!
    @IBOutlet private var episodeCodeValueLabel: UILabel!
    @IBOutlet private var airDateLabel: UILabel!
    @IBOutlet private var airDateValueLabel: UILabel!
    @IBOutlet private var createdLabel: UILabel!
    @IBOutlet private var createdValueLabel: UILabel!
    @IBOutlet private var charactersCountLabel: UILabel!
    @IBOutlet private var collectionView: UICollectionView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCollectionView()
        loadCharacters()
    }

    // MARK: - Setup

    private func setupUI() {
        guard let episode else { return }

        title = episode.name
        navigationItem.largeTitleDisplayMode = .always

        episodeCodeValueLabel.text = episode.episode
        airDateValueLabel.text = episode.airDate
        createdValueLabel.text = episode.created
    }

    private func setupCollectionView() {
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isScrollEnabled = false
    }

    // MARK: - Data Loading

    private func loadCharacters() {
        guard let episode else { return }

        Task {
            do {
                let characterIds = episode.characters.compactMap { url -> Int? in
                    guard let id = url.split(separator: "/").last else { return nil }
                    return Int(id)
                }

                characters = try await RickMortyService.shared.fetchCharactersByIds(characterIds)
                charactersCountLabel.text = "Characters: \(characters.count)"
                collectionView.reloadData()
            } catch {
                print("Error loading characters: \(error)")
            }
        }
    }
}

// MARK: - UICollectionViewDataSource

extension EpisodeDetailViewController: UICollectionViewDataSource {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        characters.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CharacterCell", for: indexPath) as! CharacterCollectionViewCell
        let character = characters[indexPath.item]
        cell.configure(with: character)
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension EpisodeDetailViewController: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let character = characters[indexPath.item]
        let storyboard = UIStoryboard(name: "CharactersView", bundle: nil)
        if let detailVC = storyboard.instantiateViewController(withIdentifier: "CharactersDetail") as? CharacterDetailViewController {
            detailVC.character = character
            navigationController?.pushViewController(detailVC, animated: true)
        }
    }
}
