/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

class CharacterCollectionViewCell: UICollectionViewCell {
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var nameLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        setupUI()
    }

    private func setupUI() {
        // Configure image view
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8

        // Configure name label
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 0
        nameLabel.lineBreakMode = .byWordWrapping
    }

    func configure(with character: Character) {
        nameLabel.text = character.name

        if let url = URL(string: character.image) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.imageView.image = image
                    }
                }
            }.resume()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        nameLabel.text = nil
    }
}
