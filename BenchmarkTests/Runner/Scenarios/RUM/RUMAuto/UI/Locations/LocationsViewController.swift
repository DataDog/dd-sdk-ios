/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import UIKit

class LocationsViewController: UIViewController {
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!

    private var locations: [Location] = []
    private var nextPageURL: String?
    private var isLoading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupNavigationBar()
        fetchLocations()
    }

    private func setupNavigationBar() {
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
    }

    private func setupCollectionView() {
        if let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            flowLayout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

            let width = UIScreen.main.bounds.width - 32
            flowLayout.itemSize = CGSize(width: width, height: 120)
        }
    }

    /// Fetches locations from the API
    private func fetchLocations() {
        guard !isLoading else { return }

        isLoading = true
        activityIndicator.startAnimating()

        Task {
            do {
                let result = try await RickMortyService.shared.fetchLocations(nextPageURL: nextPageURL)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }

                    if nextPageURL == nil {
                        locations = result.locations
                    } else {
                        locations.append(contentsOf: result.locations)
                    }

                    nextPageURL = result.nextPageURL
                    collectionView.reloadData()
                    activityIndicator.stopAnimating()
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    print("Error fetching locations: \(error)")
                    activityIndicator.stopAnimating()
                    isLoading = false

                    // Show error alert
                    let alert = UIAlertController(
                        title: "Error",
                        message: "Failed to load locations: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
                        self?.fetchLocations()
                    })
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                    present(alert, animated: true)
                }
            }
        }
    }

    /// Loads more locations when needed
    private func loadMoreIfNeeded(at indexPath: IndexPath) {
        let thresholdIndex = locations.count - 3

        if indexPath.item >= thresholdIndex, !isLoading, nextPageURL != nil {
            fetchLocations()
        }
    }
}

// MARK: - UICollectionViewDataSource

extension LocationsViewController: UICollectionViewDataSource {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        locations.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "LocationCell", for: indexPath) as? LocationCollectionViewCell else {
            return UICollectionViewCell()
        }

        cell.configure(with: locations[indexPath.item])

        // Check if we need to load more
        loadMoreIfNeeded(at: indexPath)

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionFooter {
            let footerView = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: "FooterView",
                for: indexPath
            )

            // Add loading indicator to footer if we have more pages
            if nextPageURL != nil {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                spinner.center = CGPoint(x: footerView.bounds.size.width / 2, y: footerView.bounds.size.height / 2)
                spinner.tag = 100

                // Remove any existing spinner
                if let existingSpinner = footerView.viewWithTag(100) {
                    existingSpinner.removeFromSuperview()
                }

                footerView.addSubview(spinner)
            }

            return footerView
        }

        return UICollectionReusableView()
    }
}

// MARK: - UICollectionViewDelegate

extension LocationsViewController: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let location = locations[indexPath.item]
        let storyboard = UIStoryboard(name: "LocationsView", bundle: nil)
        if let detailVC = storyboard.instantiateViewController(withIdentifier: "LocationsDetail") as? LocationDetailViewController {
            detailVC.location = location
            navigationController?.pushViewController(detailVC, animated: true)
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension LocationsViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, referenceSizeForFooterInSection _: Int) -> CGSize {
        .zero
    }
}
