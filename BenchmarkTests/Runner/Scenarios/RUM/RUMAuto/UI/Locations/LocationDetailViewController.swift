/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import UIKit

@MainActor
class LocationDetailViewController: UIViewController {
    var location: Location?
    private var residents: [Character] = []
    private var isLoading = false

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var typeLabel: UILabel!
    @IBOutlet var typeValueLabel: UILabel!
    @IBOutlet var dimensionLabel: UILabel!
    @IBOutlet var dimensionValueLabel: UILabel!
    @IBOutlet var createdLabel: UILabel!
    @IBOutlet var createdValueLabel: UILabel!
    @IBOutlet var residentsCountLabel: UILabel!
    @IBOutlet var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupUI()
        fetchResidents()
    }

    private func setupUI() {
        guard let location else {
            return
        }

        navigationItem.title = nil
        navigationItem.largeTitleDisplayMode = .never

        titleLabel.text = location.name
        typeValueLabel.text = location.type
        dimensionValueLabel.text = location.dimension
        createdValueLabel.text = formatDate(location.created)
        residentsCountLabel.text = "Residents: \(location.residents.count)"

        view.backgroundColor = .systemBackground

        for label in [typeLabel, dimensionLabel, createdLabel] {
            label?.font = .systemFont(ofSize: 15, weight: .regular)
            label?.textColor = .secondaryLabel
        }

        for label in [typeValueLabel, dimensionValueLabel, createdValueLabel] {
            label?.font = .systemFont(ofSize: 15, weight: .regular)
            label?.textColor = .label
        }

        // Set static labels
        typeLabel.text = "Type"
        dimensionLabel.text = "Dimension"
        createdLabel.text = "Created"
    }

    private func setupCollectionView() {
        collectionView.dataSource = self
        collectionView.delegate = self
    }

    private func fetchResidents() {
        guard let location, !location.residents.isEmpty else {
            return
        }

        isLoading = true

        Task {
            do {
                // Extract character IDs from URLs
                let characterIds = location.residents.compactMap { url -> Int? in
                    guard let id = url.split(separator: "/").last else {
                        return nil
                    }
                    return Int(id)
                }

                // Fetch characters in batches
                var allResidents: [Character] = []
                let batchSize = 20

                for i in stride(from: 0, to: characterIds.count, by: batchSize) {
                    let endIndex = min(i + batchSize, characterIds.count)
                    let batchIds = Array(characterIds[i ..< endIndex])
                    let batchResidents = try await RickMortyService.shared.fetchCharactersByIds(batchIds)
                    allResidents.append(contentsOf: batchResidents)
                }

                residents = allResidents
                collectionView.reloadData()
                isLoading = false
            } catch {
                print("Error fetching residents: \(error)")
                isLoading = false

                // Show error alert
                let alert = UIAlertController(
                    title: "Error",
                    message: "Failed to load residents: \(error.localizedDescription)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }
}

// MARK: - UICollectionViewDataSource

extension LocationDetailViewController: UICollectionViewDataSource {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        residents.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CharacterCell", for: indexPath) as! CharacterCollectionViewCell
        let character = residents[indexPath.item]
        cell.configure(with: character)
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension LocationDetailViewController: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let character = residents[indexPath.item]
        let characterDetailView = CharacterDetailView(character: character)
        let hostingController = UIHostingController(rootView: characterDetailView)
        navigationController?.pushViewController(hostingController, animated: true)
    }
}
