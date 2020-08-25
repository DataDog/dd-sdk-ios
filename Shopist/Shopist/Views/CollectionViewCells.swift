/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import AlamofireImage

internal final class Cell: UICollectionViewCell {
    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }
    var image: UIImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }
    func setImage(url: URL) {
        imageView.af.setImage(withURL: url)
    }

    private let imageView: UIImageView = {
        let imageView = UIImageView(frame: CGRect.zero)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()
    private let label: UILabel = {
        let label = UILabel(frame: CGRect.zero)
        label.textColor = .white
        label.font = UIFont.preferredFont(forTextStyle: .largeTitle)
        label.textAlignment = .left
        label.numberOfLines = 3
        return label
    }()
    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.cover(contentView)
        label.center(in: contentView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        image = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
