/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

final class DetailViewController: ListViewController {
    let category: Category
    private var items = [Item]()

    init(with category: Category) {
        self.category = category
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    required init?(coder: NSCoder) { fatalError() }

    override func fetch(with api: API) {
        api.getItems(for: category) { result in
            switch result {
            case .success(let items):
                self.items = items
            case .failure(let error):
                print(error)
            }
            self.reload()
        }
    }

    override func config(cell: Cell, for index: Int) {
        let item = items[index]
        var text = "\(item.id): \(item.name)\n\(item.price)"
        if item.isInStock {
            text.append(" IN STOCK!")
        }
        cell.text = text
        cell.setImage(url: item.cover)
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }
}
